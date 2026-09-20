//! Global key capture — the push-to-talk + shortcut-recorder event source.
//!
//! Wispr Flow has no hotkey detection of its own: its renderer "Keyboard
//! Service" is fed entirely by `KeypressEvent` IPC frames from the helper (the
//! macOS/Windows helpers supply them via OS key hooks). Without that stream
//! push-to-talk never fires and the in-app shortcut recorder captures nothing —
//! the two symptoms share one cause. This module produces the stream.
//!
//! One backend: [`evdev`] reads `/dev/input/event*` directly, **below** the
//! display server, so it is independent of the compositor. Needs read access
//! to the input devices (logind `uaccess` ACL or the `input` group). Each
//! press/release is translated to the Windows Virtual-Key code the app expects
//! (`keymap::evdev_to_vk`). Extra mouse buttons (middle, side, ...) go out as
//! `inputType: "mouse"` frames (`keymap::evdev_to_mouse_button`), which is what
//! lets the in-app recorder bind "Mouse 4" and friends.

mod evdev;

use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::json;

use crate::backend::EventSink;

/// Query the keys physically held right now (Windows VK codes). Used to answer
/// `CheckStaleKeys`: a key the app believes is down but that is absent here has
/// been released (or its device removed) and is stale. Backed by evdev
/// `EVIOCGKEY`.
pub trait HeldKeys {
    fn held_vks(&self) -> HashSet<u32>;
}

/// A held-keys querier that always reports nothing — used when no capture
/// backend is available (every queried key then reads as stale, which is the
/// safe answer: the app drops keys it can't confirm are held).
struct NoHeldKeys;
impl HeldKeys for NoHeldKeys {
    fn held_vks(&self) -> HashSet<u32> {
        HashSet::new()
    }
}

/// Start global key capture. Spawns the evdev reader(s) and returns a
/// [`HeldKeys`] handle for stale-key queries ([`NoHeldKeys`] when no device is
/// readable).
pub fn spawn(events: EventSink) -> Box<dyn HeldKeys> {
    match evdev::start(events) {
        Some(held) => {
            log::info!("key capture: evdev (/dev/input)");
            held
        }
        None => Box::new(NoHeldKeys),
    }
}

/// Emit one `KeypressEvent` on fd 3. `index` is a process-wide monotonic
/// sequence the app cross-checks against its own counter (it warns on a gap), so
/// every backend shares a single counter regardless of how many readers feed it.
fn emit_keypress(events: &EventSink, index: &AtomicU64, pid: u32, vk: u32, press: bool) {
    let event_type = if press {
        "key_event_press"
    } else {
        "key_event_release"
    };
    emit_input(events, index, pid, vk, event_type, "keyboard");
}

/// Emit one mouse-button `KeypressEvent`. `button` is the app's OS button
/// number (2 = middle, 3 = "Mouse 4", 4 = "Mouse 5", ...), which its keyboard
/// service translates to its own mouse keycodes. Shares the keypress counter.
fn emit_mouse_button(events: &EventSink, index: &AtomicU64, pid: u32, button: u32, press: bool) {
    let event_type = if press {
        "mouse_event"
    } else {
        "mouse_event_release"
    };
    emit_input(events, index, pid, button, event_type, "mouse");
}

fn emit_input(
    events: &EventSink,
    index: &AtomicU64,
    pid: u32,
    key: u32,
    event_type: &str,
    input_type: &str,
) {
    let idx = index.fetch_add(1, Ordering::Relaxed) + 1;
    let env = crate::proto::request(
        "KeypressEvent",
        json!({ "payload": {
            "eventType": event_type,
            "key": key,
            "index": idx,
            "inputType": input_type,
        } }),
        &format!("kp-{pid}-{idx}"),
    );
    let _ = events.send(env);
}

#[cfg(test)]
mod tests {
    use super::*;

    // The exact `KeypressEvent` frame shape is the contract the app's keyboard
    // service decodes; pin it so silent protocol drift fails the build.
    #[test]
    fn emit_keypress_builds_keypress_event_frame() {
        let (tx, rx) = std::sync::mpsc::channel();
        let index = AtomicU64::new(0);

        emit_keypress(&tx, &index, 4242, 65, true);
        emit_keypress(&tx, &index, 4242, 65, false);

        let press = rx.recv().expect("press frame");
        let kp = &press["HelperAPIRequest"]["KeypressEvent"]["payload"];
        assert_eq!(kp["eventType"], "key_event_press");
        assert_eq!(kp["key"], 65);
        assert_eq!(kp["index"], 1); // counter starts at 1, not 0
        assert_eq!(kp["inputType"], "keyboard");
        assert_eq!(press["HelperAPIRequest"]["uuid"], "kp-4242-1");

        let release = rx.recv().expect("release frame");
        let kp = &release["HelperAPIRequest"]["KeypressEvent"]["payload"];
        assert_eq!(kp["eventType"], "key_event_release");
        assert_eq!(kp["index"], 2); // shared monotonic counter advances
        assert_eq!(release["HelperAPIRequest"]["uuid"], "kp-4242-2");
    }

    // Mouse buttons use their own event/input types; the app ignores the key
    // number unless `inputType` is "mouse".
    #[test]
    fn emit_mouse_button_builds_mouse_event_frame() {
        let (tx, rx) = std::sync::mpsc::channel();
        let index = AtomicU64::new(0);

        emit_mouse_button(&tx, &index, 4242, 3, true);
        emit_mouse_button(&tx, &index, 4242, 3, false);

        let press = rx.recv().expect("press frame");
        let kp = &press["HelperAPIRequest"]["KeypressEvent"]["payload"];
        assert_eq!(kp["eventType"], "mouse_event");
        assert_eq!(kp["key"], 3);
        assert_eq!(kp["index"], 1);
        assert_eq!(kp["inputType"], "mouse");

        let release = rx.recv().expect("release frame");
        let kp = &release["HelperAPIRequest"]["KeypressEvent"]["payload"];
        assert_eq!(kp["eventType"], "mouse_event_release");
        assert_eq!(kp["index"], 2);
    }
}
