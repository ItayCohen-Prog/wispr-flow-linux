[< Back to docs index](index.md)

# Decision Log

Hey! This is where I park the architectural calls that shape the Wispr Flow for
Linux port. What I picked, why I picked it, and what I turned down. It's an
ADR-format log, so each entry stays put.

I don't delete decisions. If I revisit one, I mark it `Superseded` and link
forward to the new one. Every entry carries a stable ID (`D-NNN`), a status, a
decision date, and an owner.

## Index

| ID | Date | Status | Title |
|---|---|---|---|
| [D-001](#d-001--rust-for-the-clean-room-helper) | 2026-06-04 | Accepted | Rust for the clean-room helper |
| [D-002](#d-002--in-process-devuinput-virtual-keyboard) | 2026-06-04 | Accepted | In-process `/dev/uinput` virtual keyboard |
| [D-003](#d-003--clipboard-based-paste-not-per-character-typing) | 2026-06-04 | Accepted | Clipboard-based paste, not per-character typing |
| [D-004](#d-004--at-spi-as-the-universal-active-app--selection-fallback) | 2026-06-04 | Accepted | AT-SPI as the universal active-app / selection fallback |
| [D-005](#d-005--per-compositor-active-app-providers) | 2026-06-04 | Accepted | Per-compositor active-app providers |
| [D-006](#d-006--rename-the-electron-launcher-to-wispr-flow) | 2026-06-04 | Accepted | Rename the Electron launcher to `wispr-flow` |
| [D-007](#d-007--clean-room-v8-148-patch-for-better-sqlite3-multiple-ciphers) | 2026-06-04 | Accepted | Clean-room V8 14.8 patch for `better-sqlite3-multiple-ciphers` |
| [D-008](#d-008--async-zbus-on-tokio-never-zbusblocking-for-services) | 2026-06-04 | Accepted | Async zbus on tokio, never `zbus::blocking` for services |
| [D-009](#d-009--native-sqlite-addons-as-pinned-prebuilt-assets-not-a-build-time-rebuild) | 2026-06-06 | Accepted | Native sqlite addons as pinned prebuilt assets, not a build-time rebuild |
| [D-010](#d-010--the-flow-bar-is-drawn-by-the-shell-on-omarchy-not-by-electron) | 2026-08-29 | Accepted | The Flow Bar is drawn by the shell on Omarchy, not by Electron |

---

## D-001 — Rust for the clean-room helper

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

Wispr Flow ships its text-injection "Helper" only as macOS (Swift) and Windows
(C#) binaries. No Linux variant, and no source. I looked at the documented IPC
contract ([`reference/ipc-contract.md`](reference/ipc-contract.md)), and it
captures the whole interface. The helper is a thin shim over standard
desktop-automation primitives with **zero proprietary algorithms**. So the Linux
helper had to be written from scratch.

### Decision

I wrote the Linux helper fresh in **Rust** (it started in this repo, now it's its
own repo
[github.com/wispr-flow-linux/helper](https://github.com/wispr-flow-linux/helper)).
I built it against the documented IPC contract (`docs/reference/`), not by
porting the C#.

### Rationale

- **Single static binary, no runtime.** A Rust helper ships as one executable.
  There's no .NET runtime to bundle or version-match.
- **Raw `libc` ioctls for uinput** keep the binary dependency-free. No extra C
  deps, so it stays a single static binary.
- **Clean-room provenance.** I wrote from the documented IPC contract, not from
  the binary, so the helper carries no Wispr Flow code.
- **Mature Wayland/D-Bus/AT-SPI crates** (`wayland-client`, `zbus`, `atspi`)
  cover the hard surfaces.

### Consequences

- The helper is an independent reimplementation. It contains no upstream code.
- There's one ecosystem pin to manage: `atspi 0.22` is pinned to keep a single
  `zbus 4.x` in the tree (see
  [D-008](#d-008--async-zbus-on-tokio-never-zbusblocking-for-services)).

### References

- [`reference/ipc-contract.md`](reference/ipc-contract.md) — the IPC contract;
  [learnings/wayland-injection.md](learnings/wayland-injection.md).

---

## D-002 — In-process `/dev/uinput` virtual keyboard

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

Keystroke injection on Wayland has no XTEST equivalent that reaches native
surfaces. I had a few options. There's `ydotool` (uinput via a daemon, needs
perms), `wtype`, or the `libei`/portal RemoteDesktop path. That last one is the
newest, but compositor support is still uneven.

### Decision

I inject at the **kernel input layer**. The helper creates an **in-process
`/dev/uinput` virtual keyboard** and writes evdev events. libinput → compositor
routes them to the focused surface like a real keyboard. It's **in-process, no
`ydotoold` daemon, no root**.

### Rationale

- **Sidesteps the display-server gap.** Inject below the compositor and you
  reach every native Wayland surface. XTEST can't do that.
- **No daemon, no root.** You only need write access to `/dev/uinput`. The
  active-session user gets it via the logind `uaccess` udev rule, or the `input`
  group as a cross-distro fallback. That's a far smaller ambient capability than
  running a privileged daemon.

### Consequences

- **Accepted trade-off:** the port now leans on a udev rule plus `/dev/uinput`
  access. The packages ship the rule, and `--doctor` checks it. Without access,
  injection is dead. It fails loud, and the fix is clear.
- A ~200 ms settle delay is required so the compositor enumerates the device
  before the first event. Skip it and early keys drop.

### References

- [learnings/wayland-injection.md](learnings/wayland-injection.md).

---

## D-003 — Clipboard-based paste, not per-character typing

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

`PasteText` had two shapes. Either (a) set the clipboard and synth Ctrl+V, or
(b) type the text out character-by-character via synthetic key events. The
documented contract settles which one the upstream app does. It's the clipboard
path.

### Decision

I implemented `PasteText` as **clipboard-based**. The helper owns the clipboard
with `text/plain` + `text/html`, synths a Ctrl+V chord, and optionally restores
the prior clipboard. That matches the Windows helper exactly.

### Rationale

- **Matches upstream.** The Windows helper does `OpenClipboard` (with
  exponential backoff) → set `CF_UNICODETEXT` + `CF_TEXT` → `SendInput` Ctrl+V.
  Replicating it keeps behavior consistent.
- **Robust to text content.** Per-character synthesis has to map every character
  to keysyms and modifiers. Clipboard paste delivers arbitrary Unicode (and rich
  text) atomically.
- **Easier on Wayland.** The in-process clipboard owner via
  `ext_data_control_manager_v1` is focus-free, and it pairs naturally with the
  uinput Ctrl+V chord.

### Consequences

- The helper temporarily owns the clipboard. It restores the prior contents
  where it can (reads still shell out to `wl-paste`).
- Clipboard set replicates the Windows retry/backoff so it survives lock
  contention.

### References

- [`reference/ipc-contract.md`](reference/ipc-contract.md) —
  the `PasteText` mechanism.

---

## D-004 — AT-SPI as the universal active-app / selection fallback

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

`GetSelectedTextViaCopy` originally used a destructive Ctrl+C copy-probe, which
mutates the clipboard. And on Wayland compositors with no KDE/GNOME bridge (Sway,
Hyprland), there's no portable "focused app" protocol at all.

### Decision

I use **AT-SPI2** as the proper, non-destructive selection reader. It reads the
focused accessible's `Text` interface over the a11y bus. It also serves as the
**universal active-app provider for non-KDE/GNOME compositors**. The Ctrl+C
copy-probe stays, but only as a fallback.

### Rationale

- **Non-destructive selection.** AT-SPI reads the selection without touching the
  clipboard or synthesizing keys.
- **Compositor-agnostic.** Where there's no KWin/GNOME bridge, AT-SPI is the only
  thing that exposes window/app identity portably.

### Consequences

- The helper has to call `set_session_accessibility(true)` (it's idempotent) so
  toolkits expose their trees. That includes KDE, where the active-app provider
  is the KWin bridge and nothing else flips the a11y flag.
- **Accepted limit:** apps with no a11y bridge (bare terminals, some Electron)
  won't resolve. Those windows degrade to empty.

### References

- [compatibility.md](compatibility.md) — AT-SPI backend coverage.

---

## D-005 — Per-compositor active-app providers

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

Wayland exposes no portable "which app is focused" API. Each desktop has its own
mechanism, and none of them generalizes to the others.

### Decision

I ship **three active-app/focus providers**, selected by environment:

- **KDE** — a KWin script pushes `windowActivated` / window-list over D-Bus to a
  helper-hosted zbus service.
- **GNOME** — a GNOME Shell extension bridging `org.gnome.Shell.Introspect`.
- **wlroots / other** — AT-SPI (see [D-004](#d-004--at-spi-as-the-universal-active-app--selection-fallback)).
- **X11** — `_NET_*` window properties + XTEST.

Injection, clipboard, and selection are shared across all of them. Only
active-app/focus is per-compositor.

### Rationale

- **There is no single answer.** KWin scripting, GNOME Introspect, and AT-SPI are
  the only reliable per-desktop sources. Force one onto all compositors and it
  fails.
- **GNOME Introspect over AT-SPI on GNOME** because mutter exposes a richer, more
  reliable focus signal there.

### Consequences

- Three bridges to maintain, each with its own install/permission story. The
  GNOME extension needs a relogin, and KDE's KWin `callDBus` can be
  intermittently delayed.
- `detect()` routing has to be careful. For example, treat an empty
  `WAYLAND_DISPLAY` as unset, and route Ubuntu's `ubuntu:GNOME` to the GNOME
  path.

### References

- [learnings/kwin-zbus-tokio.md](learnings/kwin-zbus-tokio.md);
  [learnings/gnome-shell-extension.md](learnings/gnome-shell-extension.md).

---

## D-006 — Rename the Electron launcher to `wispr-flow`

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

I staged a Linux Electron whose launcher was named `electron`, and every DB
query failed with "no such table". The log read "Executed 0 migrations". That
took me a while to track down.

### Decision

I **rename the Electron binary off `electron`** (to `wispr-flow`) in every
packaging path, and I export `ELECTRON_FORCE_IS_PACKAGED=true` from the launcher
on top of that.

### Rationale

- Electron sets `app.isPackaged=false` when the launcher is literally named
  `electron`. The app then resolves the *dev* migrations path (which is absent),
  runs 0 migrations, and every table is missing. Rename the binary and
  `isPackaged` flips to `true`. That gets you the packaged migrations path, and
  all 92 migrations run.
- `ELECTRON_FORCE_IS_PACKAGED=true` is belt-and-braces in case a layout slips the
  rename.

### Consequences

- The makers have to preserve the rename and the exec bit. The helper-path patch
  uses `process.resourcesPath` directly, so the helper works either way. Only
  migrations depend on `isPackaged`.

### References

- [learnings/ispackaged-rename.md](learnings/ispackaged-rename.md).

---

## D-007 — Clean-room V8 14.8 patch for `better-sqlite3-multiple-ciphers`

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

Electron 42 ships V8 14.8 / Node 24.15. `better-sqlite3-multiple-ciphers@12.5.0`
won't compile against V8 14.8 unpatched. Upstream Wispr Flow fixes this with a
pinned yarn patch.

### Decision

I ship a **clean-room equivalent** patch
(`scripts/patches/v8-14.8-better-sqlite3-multiple-ciphers.patch`), applied to a
pristine 12.5.0 before `@electron/rebuild`.

### Rationale

- Three version-guarded V8-API fixes restore compilation:
  `External::New()/Value()` external-pointer tag, `PropertyCallbackInfo::This()`
  → `HolderV2()`, and the `SetNativeDataProperty` `0`→`nullptr` ambiguity.
- I wrote it independently, not copied from upstream's yarn patch, so the
  clean-room provenance holds.

### Consequences

- It's runtime-validated under Electron 42. It opens an encrypted SQLCipher DB,
  all three patched getters come back correct, and a wrong key gets rejected. The
  patch is version-guarded, so it's a no-op on V8 versions that don't need it.

### References

- [learnings/electron42-v8-sqlite.md](learnings/electron42-v8-sqlite.md).

---

## D-008 — Async zbus on tokio, never `zbus::blocking` for services

- **Status:** Accepted
- **Decided:** 2026-06-04
- **Owner:** @aaddrick

### Context

The KDE bridge first hosted a zbus **blocking** service. KWin's `Report` /
`ReportList` callbacks queued up and only flushed at shutdown. So KDE active-app
and running-apps came back empty. That one cost me a real debugging session.

### Decision

I host every zbus **service** on the **async** zbus API inside a dedicated tokio
runtime. **Never** use `zbus::blocking` for a service in this codebase.

### Rationale

- `atspi` enables zbus's `tokio` feature tree-wide, and that disables zbus's
  internal async-io executor thread. A blocking service connection then never
  dispatches *incoming* method calls, except while we make an outgoing blocking
  call. So KWin's callbacks never ran.
- Run on the async API on a live tokio runtime and incoming calls dispatch
  promptly.

### Consequences

- It's a codebase rule now: zbus services run async-on-tokio (mirrors
  `atspi_app.rs`).
- This is the single most load-bearing concurrency invariant in the helper.

### References

- [learnings/kwin-zbus-tokio.md](learnings/kwin-zbus-tokio.md).

---

## D-009 — Native sqlite addons as pinned prebuilt assets, not a build-time rebuild

- **Status:** Accepted
- **Decided:** 2026-06-06
- **Owner:** @aaddrick

### Context

The app ships Windows `.node` for `better-sqlite3-multiple-ciphers` + `sqlite3`;
Linux needs them rebuilt for the Electron 42 ABI (the V8 14.8 patch from
[D-007](#d-007--clean-room-v8-148-patch-for-better-sqlite3-multiple-ciphers)).
The first cut only *documented* the rebuild and swapped in `.node` from a
gitignored dir — empty in CI, so the build shipped Windows `.node` and crashed
at startup. The obvious fix (rebuild inside each package job) is non-reproducible
(no lockfile), a per-build supply-chain + network surface, and — decisively —
bakes the **build runner's glibc** into the binary, so a `.node` built on a new
CI image fails to load on older-but-supported distros.

### Decision

Treat the addons like the clean-room helper: build them **once**, per arch, on an
old-glibc base, and consume them as pinned, checksummed, provenance-stamped
release assets.

- Producer: the **Build Native Modules** workflow in the dedicated
  `wispr-flow-linux/native-modules` repo builds on `manylinux_2_28` (glibc 2.28
  floor) via `scripts/rebuild-native-modules.sh` (lockfile-pinned `npm ci`, the
  V8 patch on a pristine checkout, isolated electron-gyp headers), validates
  under real Electron 42 (ABI 146 + encrypted-DB round-trip), and publishes to
  the tag pinned in `native-modules-version.txt`. The build lives in its own repo
  (like the helper) so these CI-consumed assets don't inflate the main project's
  Release download counts.
- Consumer: `scripts/setup/fetch-native-bin.sh` (`NATIVE_REPO` →
  `wispr-flow-linux/native-modules`) verifies SHA-256 + the
  `native-modules.lock` provenance (asset `patch_sha256` == this checkout's
  patch; ABI 146) before staging. CI hard-fails on fetch failure.

### Rationale

- Reproducible (committed `package-lock.json`, `npm ci`), and the glibc floor is
  a deliberate choice (the build image) instead of an accident (the CI runner).
- The provenance stamp — not ELF magic — is the trust anchor: a stale or
  wrong-ABI `.node` is ELF-valid but provenance-mismatched, and is rejected.
- Mirrors the established `HELPER_BIN` / `helper-version.txt` pattern.

### Consequences

- A new Electron/package bump means re-running the producer workflow and bumping
  `native-modules-version.txt` — a deliberate, reviewable step.
- `build-linux.sh` keeps an **opt-in** local from-source rebuild (host glibc,
  `WISPR_NATIVE_REBUILD=1`) for dev convenience only; the default never rebuilds
  and CI never does. `rebuild-native-modules.sh` + `scripts/native-modules/` +
  the V8 patch stay vendored here (the patch is also the consumer's provenance
  anchor) and are kept in sync with the `native-modules` repo's canonical copy.

### References

- [learnings/electron42-v8-sqlite.md](learnings/electron42-v8-sqlite.md),
  [building.md](building.md#native-sqlite-modules-prebuilt-with-an-opt-in-local-rebuild).

---

## D-010 — The Flow Bar is drawn by the shell on Omarchy, not by Electron

- **Status:** Accepted
- **Decided:** 2026-08-29
- **Owner:** @ItayCohen-Prog

### Context

The Flow Bar is a transparent, always-on-top Electron window ("Flow Status
Indicator") whose renderer also owns microphone capture. Native Wayland gives
an Electron window no say over its position or input region, so on Wayland
sessions the launcher pins the whole app to XWayland and
`linux-flowbar-shape.sh` crops the X11 surface to the visible bar. That works,
but it costs the rest of the app: XWayland has one device scale for every
monitor (a 1× and a 1.6× panel cannot both be right), and the Hub — created
`focusable:false` upstream — becomes an X11 override-redirect window that
Hyprland cannot tile, move, resize or focus (#36; `linux-hub-focusable.sh`
patches that for the XWayland path).

A layer-shell surface anchored to the bottom of the focused monitor is what the
bar has been emulating all along, and omarchy-shell (Quickshell) can host one
as a user plugin.

### Decision

On Omarchy the shell draws the bar and Electron runs on native Wayland.

- `scripts/patches/linux-native-flowbar.sh` (main bundle) mirrors every
  `status:*` / `notification:*` IPC message main sends to the status window
  over `$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock` as newline-delimited JSON
  (`{"t":channel,"p":payload}`), re-emits `status:startClicked|stopClicked|
  cancelClicked` and `notification:callback` received from the socket on
  `ipcMain`, and never maps the Electron status window. The block is gated on
  `WISPR_NATIVE_FLOWBAR=1`; without it the bundle behaves as before.
- `omarchy/plugins/wispr.flowbar/` serves the socket and renders the pill
  (cancel, level meter, stop) in a `PanelWindow` on the focused monitor with an
  input mask limited to the pill. Notifications go to the desktop notification
  daemon via `notify-send`; a toast click runs the app's primary action.
- The launcher picks `--ozone-platform=wayland` when the socket exists
  (`WISPR_NATIVE_FLOWBAR=0|1` overrides), so the switch follows the plugin
  being installed rather than a flag the user has to remember.
- `scripts/extract-flowbar-strings.sh` ships the status renderer's English
  string table as `resources/flowbar-strings.en.json` so i18n `{key}`
  notification texts render natively.

### Rationale

- The proprietary app keeps everything that matters to Wispr: login, backend,
  Hub UI and audio capture (the hidden status renderer still calls
  `getUserMedia`). Only the on-screen overlay moves, and it moves to the
  component that can position it.
- Mirroring the IPC verbatim keeps the protocol a description of upstream's
  own channels instead of a new one to maintain; the reducer in
  `FlowBarModel.js` keys on `status:dictationStatus`, `status:setIndicatorState`,
  `status:audioLevel` and `notification:show|clear`.
- The shell is the socket server and the app a reconnecting client because
  the shell outlives app restarts, and its socket doubles as the "native mode
  available" signal the launcher checks.
- Notifications use the daemon rather than a second layer-shell surface so
  history, do-not-disturb and theming apply as for any other app. Omarchy's
  daemon renders no named action buttons, only the freedesktop `default`
  click action, so the primary action maps to a toast click.
- Native Wayland removes the unmanaged-Hub and single-scale problems outright
  instead of patching around them; `linux-hub-focusable.sh` and
  `linux-flowbar-shape.sh` stay for the XWayland fallback on every other
  compositor.

### Consequences

- Omarchy-only for now: the plugin depends on omarchy-shell's plugin loader,
  `Quickshell.Hyprland.focusedMonitor` and `notify-send`. Other Wayland
  desktops keep the XWayland path.
- Custom-component notifications (upstream renders a bespoke React view for
  e.g. `AudioQualityIssue`) show text only; their in-component click behaviour
  is not reproduced.
- The plugin directory is a symlink into the repo; omarchy-shell does not
  hot-reload code behind a symlink, so edits need `omarchy restart shell`.
- Startup order does not matter: the bridge reconnects every 2 s and queues
  up to 50 lines, so the shell can restart under a running app.

### References

- [configuration.md](configuration.md#native-flow-bar-on-omarchy),
  [troubleshooting.md](troubleshooting.md),
  [`omarchy/plugins/wispr.flowbar/README.md`](../omarchy/plugins/wispr.flowbar/README.md),
  [learnings/patching-minified-js.md](learnings/patching-minified-js.md),
  issue #36.
