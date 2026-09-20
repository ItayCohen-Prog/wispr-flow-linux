//! OS-integration backend abstraction.
//!
//! Target session: Hyprland (wlroots-style Wayland) on Arch/Omarchy. One
//! injection backend (`wayland`: uinput + in-process clipboard) composed with
//! the AT-SPI active-app tracker; a no-op `stub` keeps the IPC handshake alive
//! when `/dev/uinput` is not usable. The protocol/dispatch layer (main.rs,
//! proto.rs) stays backend-agnostic.

pub mod atspi_app;
pub mod atspi_sel;
pub mod stub;
pub mod uinput;
pub mod wayland;
pub mod wl_clipboard;

pub type Result<T> = std::result::Result<T, String>;

/// Channel a backend uses to push **helper-initiated** events to fd 3 (e.g.
/// `AppInfoUpdate` focus events). A single writer thread owns fd 3 and drains
/// this, so emitting from any thread (e.g. the AT-SPI watcher) is safe.
pub type EventSink = std::sync::mpsc::Sender<serde_json::Value>;

/// Clipboard paste chord selected by Wispr's `shift-insert` feature flag.
/// Terminals treat a raw Ctrl+V key event as an application shortcut (Codex
/// uses it for image paste), while Shift+Insert is handled by the terminal as
/// text paste and arrives as bracketed paste input.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum PasteShortcut {
    ControlV,
    #[default]
    ShiftInsert,
}

impl PasteShortcut {
    pub(crate) fn from_shift_insert(enabled: bool) -> Self {
        if enabled {
            Self::ShiftInsert
        } else {
            Self::ControlV
        }
    }

    pub(crate) fn key_vk(self) -> u32 {
        match self {
            Self::ControlV => b'V' as u32,
            Self::ShiftInsert => 45,
        }
    }

    pub(crate) fn modifier(self) -> &'static str {
        match self {
            Self::ControlV => "Control",
            Self::ShiftInsert => "Shift",
        }
    }
}

/// Result of `GetActiveAppInfo` / `GetAppInfo` (subset we can fill on Linux).
#[derive(Debug, Default, Clone)]
pub struct ActiveApp {
    pub app_name: String,
    /// No real "bundle id" on Linux — we use the exe basename / app name.
    pub bundle_id: String,
    pub window_title: String,
    /// Browser URL if derivable (else empty). Not wired yet.
    pub url: String,
}

/// Result of `GetSelectedTextViaCopy`.
#[derive(Debug, Default, Clone)]
pub struct Selection {
    pub selected_text: String,
    pub before_text: String,
    pub after_text: String,
    pub contents: String,
}

/// A running app entry for `GetRunningApps` (bundleId, name).
#[derive(Debug, Clone)]
pub struct RunningApp {
    pub bundle_id: String,
    pub name: String,
}

pub trait Backend: Send {
    /// `PasteText`: set the clipboard to `text` (+ optional `html`) and synthesize
    /// the configured paste shortcut.
    fn paste_text(&mut self, text: &str, html: Option<&str>) -> Result<()>;

    /// `SimulateKeyPress`: `keycode` is a **Windows VK code** (see keymap.rs); `flags`
    /// are modifier names ("Control"/"Shift"/"Alt"/"Command").
    fn simulate_key_press(&mut self, keycode_vk: u32, flags: &[String]) -> Result<()>;

    /// `GetActiveAppInfo` / `GetAppInfo`.
    fn get_active_app(&mut self) -> Result<ActiveApp>;

    /// `GetRunningApps`.
    fn get_running_apps(&mut self) -> Result<Vec<RunningApp>>;

    /// `GetSelectedTextViaCopy`: copy-based selection probe (save clipboard, Ctrl+C, read, restore).
    fn get_selected_text(&mut self) -> Result<Selection>;

    /// `GetAccessibilityStatus`: whether the accessibility/automation path is usable.
    fn accessibility_status(&mut self) -> bool;

    /// Select the clipboard paste chord. Wispr sends this through
    /// `UpdateFeatureFlags` before normal dictation begins.
    fn set_shift_insert(&mut self, enabled: bool) {
        let _ = enabled;
    }

    /// `SetFocusChangeDetectorState`: enable/disable emitting `AppInfoUpdate`
    /// focus events on fd 3. Default no-op for backends without focus tracking.
    fn set_focus_detection(&mut self, active: bool) {
        let _ = active;
    }

    fn name(&self) -> &'static str;
}

/// Build the `{ "payload": { appName, bundleId, windowTitle, url } }` body shared
/// by `ActiveAppInfo`/`AppInfo` responses and `AppInfoUpdate` events.
///
/// `codingCliAgent` / `codingCliAgentConfidence` are OPTIONAL enums; the app's
/// validator rejects a present-but-null optional, so we OMIT them (absent ==
/// undefined == accepted) until terminal/CLI-agent detection lands.
pub fn active_app_payload(a: &ActiveApp) -> serde_json::Value {
    serde_json::json!({ "payload": {
        "appName": a.app_name,
        "bundleId": a.bundle_id,
        "windowTitle": a.window_title,
        "url": a.url,
    } })
}

/// Composes the injection backend with the AT-SPI active-app tracker.
/// Injection, clipboard, and selection delegate to `inner`; active-app /
/// running-apps / focus come from `inner` **first** and fall back to the
/// tracker (the Wayland injector returns empty for all three, so in practice
/// the tracker supplies identity, and it is the only source of focus events).
struct Composed {
    inner: Box<dyn Backend>,
    tracker: atspi_app::AtspiTracker,
}

impl Backend for Composed {
    fn paste_text(&mut self, text: &str, html: Option<&str>) -> Result<()> {
        self.inner.paste_text(text, html)
    }

    fn simulate_key_press(&mut self, keycode_vk: u32, flags: &[String]) -> Result<()> {
        self.inner.simulate_key_press(keycode_vk, flags)
    }

    fn get_active_app(&mut self) -> Result<ActiveApp> {
        let inner = self.inner.get_active_app().unwrap_or_default();
        if !inner.app_name.is_empty()
            || !inner.bundle_id.is_empty()
            || !inner.window_title.is_empty()
        {
            return Ok(inner);
        }
        if let Some(app) = self.tracker.current() {
            return Ok(app);
        }
        Ok(inner)
    }

    fn get_running_apps(&mut self) -> Result<Vec<RunningApp>> {
        let inner = self.inner.get_running_apps().unwrap_or_default();
        if !inner.is_empty() {
            return Ok(inner);
        }
        Ok(self.tracker.get_running_apps())
    }

    fn get_selected_text(&mut self) -> Result<Selection> {
        self.inner.get_selected_text()
    }

    fn accessibility_status(&mut self) -> bool {
        self.inner.accessibility_status()
    }

    fn set_shift_insert(&mut self, enabled: bool) {
        self.inner.set_shift_insert(enabled);
    }

    fn set_focus_detection(&mut self, active: bool) {
        // Forward to both: the inner backend no-ops; the tracker is what
        // actually emits `AppInfoUpdate` focus events.
        self.inner.set_focus_detection(active);
        self.tracker.set_focus_detection(active);
    }

    fn name(&self) -> &'static str {
        self.inner.name()
    }
}

/// Pick a backend for the current session: the injection backend and (when the
/// a11y bus is reachable) the AT-SPI active-app tracker, chosen
/// **independently** and composed — so active-window identity survives an
/// injection-less session (no `/dev/uinput` access).
pub fn detect(events: EventSink) -> Box<dyn Backend> {
    let tracker = pick_active_app_tracker(events);
    let injector = pick_injector();
    match tracker {
        Some(t) => {
            log::info!(
                "backend: {} injection + atspi active-app provider",
                injector.name()
            );
            Box::new(Composed {
                inner: injector,
                tracker: t,
            })
        }
        None => {
            log::info!("backend: {} (no active-app provider)", injector.name());
            injector
        }
    }
}

/// True iff env var `var` is set to a **non-empty** value. An empty
/// `WAYLAND_DISPLAY` (some launchers/sessions export a blank value) must be
/// treated as unset: `var_os(...).is_some()` is `true` for an empty value,
/// which would make `detect()` try the Wayland backend and fail injection
/// ("could not find wayland compositor").
fn env_set(var: &str) -> bool {
    std::env::var_os(var).is_some_and(|v| !v.is_empty())
}

/// Choose the injection/clipboard/selection backend for this session: Wayland
/// (uinput + clipboard) when `$WAYLAND_DISPLAY` is set and `/dev/uinput` is
/// writable, else the no-op stub that keeps the helper handshaking.
fn pick_injector() -> Box<dyn Backend> {
    if env_set("WAYLAND_DISPLAY") {
        if uinput::UInput::available() {
            match wayland::WaylandBackend::connect() {
                Ok(b) => {
                    log::info!("injection: Wayland (uinput + wl-clipboard)");
                    return Box::new(b);
                }
                Err(e) => log::error!("Wayland backend init failed, falling back to stub: {e}"),
            }
        } else {
            log::warn!(
                "Wayland session but /dev/uinput is not writable — injection unavailable. \
                 Grant access via a logind uaccess udev rule or the `uinput` group."
            );
        }
    } else {
        log::warn!("WAYLAND_DISPLAY is not set — injection unavailable");
    }
    log::warn!("injection: stub (no-op) — OS integration disabled");
    Box::new(stub::StubBackend)
}

/// Start the AT-SPI active-app tracker — independent of injection. `None` when
/// the accessibility bus is unreachable.
fn pick_active_app_tracker(events: EventSink) -> Option<atspi_app::AtspiTracker> {
    if !env_set("WAYLAND_DISPLAY") {
        return None;
    }
    match atspi_app::AtspiTracker::start(events) {
        Ok(t) => {
            log::info!("active-app: AT-SPI tracker");
            Some(t)
        }
        Err(e) => {
            log::warn!("AT-SPI active-app unavailable ({e})");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::PasteShortcut;

    #[test]
    fn paste_shortcut_uses_shift_insert_when_enabled() {
        let shortcut = PasteShortcut::from_shift_insert(true);
        assert_eq!(shortcut.key_vk(), 45);
        assert_eq!(shortcut.modifier(), "Shift");
    }

    #[test]
    fn paste_shortcut_startup_default_is_shift_insert() {
        let shortcut = PasteShortcut::default();
        assert_eq!(shortcut.key_vk(), 45);
        assert_eq!(shortcut.modifier(), "Shift");
    }

    #[test]
    fn disabled_shift_insert_flag_selects_control_v() {
        let shortcut = PasteShortcut::from_shift_insert(false);
        assert_eq!(shortcut.key_vk(), b'V' as u32);
        assert_eq!(shortcut.modifier(), "Control");
    }
}
