# wispr-flow-linux-helper

> Standalone repo (`github.com/wispr-flow-linux/helper`), split out of the
> `wispr-flow-linux` monorepo. Tagged `v*` releases publish prebuilt
> `wispr-flow-linux-helper-x86_64` and `wispr-flow-linux-helper-aarch64`
> binaries as Release assets, which the main `wispr-flow-linux` package build
> downloads instead of compiling the helper itself.

Clean-room Linux helper for Wispr Flow. It is a standalone process that speaks
the helper IPC contract the Wispr Flow Electron app uses for its macOS (Swift)
and Windows (C#) helpers. The app ships no Linux helper; this fills that gap.

Target platform: **Hyprland** (wlroots-style Wayland compositor) on Arch Linux /
Omarchy. GNOME, KDE and X11 are not supported.

**Contract is the source of truth:**
[`docs/reference/ipc-contract.md`](https://github.com/wispr-flow-linux/wispr-flow-linux/blob/main/docs/reference/ipc-contract.md)
(+ `keycodes.json`, `commands.json`), kept in the main `wispr-flow-linux` repo.

## How it works

Wire protocol: commands arrive on **stdin (fd 0)**; all responses and
helper-initiated events go out on **fd 3**; stderr is logging; stdout is never
used for IPC.

| Command | Implementation |
|---|---|
| `IsReady` -> `ACK` | handshake + keepalive |
| `PasteText` | in-process clipboard owner (`ext-data-control`, text/plain + text/html; `wl-copy` fallback) + uinput Shift+Insert (Ctrl+V when the `shift-insert` feature flag is off) |
| `SimulateKeyPress` | Windows VK -> evdev code -> uinput chord (waits for physically held modifiers to come up) |
| `GetActiveAppInfo` / `GetAppInfo` / `GetRunningApps` | AT-SPI accessibility bus: focused application via `window:activate` / `object:state-changed:focused`, PID -> `/proc` for name and exe |
| `SetFocusChangeDetectorState` -> `AppInfoUpdate` | AT-SPI focus events on fd 3, gated and deduplicated |
| `GetSelectedTextViaCopy` | AT-SPI `Text` interface read of the focused widget's selection; fallback: save clipboard, uinput Ctrl+C, `wl-paste`, restore |
| `GetAccessibilityStatus` | true when the uinput device is live |
| `CheckStaleKeys` | evdev `EVIOCGKEY` snapshot of physically held keys |
| `KeypressEvent` (helper -> app) | global key capture from `/dev/input/event*` (evdev), translated to Windows VK codes; drives push-to-talk and the shortcut recorder |
| everything else | ACK no-op, so the unmodified app stays healthy |

Backend selection (`src/backend/mod.rs::detect`):

* Injection: Wayland backend when `$WAYLAND_DISPLAY` is set (non-empty) and
  `/dev/uinput` is writable; otherwise a no-op stub that still answers the
  handshake.
* Active app / focus: the AT-SPI tracker, started independently of injection
  when `$WAYLAND_DISPLAY` is set and the a11y bus is reachable. If it is not,
  active-app fields come back empty and no focus events are emitted.

Requirements on the host:

* `/dev/uinput` write access and `/dev/input/event*` read access for the
  session user (logind `uaccess` udev rule, or the `uinput` / `input` groups).
* `wl-clipboard` (`wl-copy`, `wl-paste`) for clipboard reads and the fallback
  write path.
* `at-spi2-core` (the accessibility bus). The helper sets
  `org.a11y.Status.IsEnabled` so GTK/Qt apps expose their trees; apps without an
  a11y bridge (many Electron apps, some terminals) report empty identity.

## Build

```bash
cargo build --release   # -> target/release/wispr-flow-linux-helper
cargo test
cargo clippy --all-targets -- -D warnings
```

All dependencies are pure Rust (no libdbus, libX11 or libwayland headers).
`--version` prints the crate version and exits without touching fd 3 or the
input devices; the app's `--doctor` uses it as a link/launch probe.

## Layout

```
src/
  main.rs            entry: stdin reader, fd3 writer, dispatch, IsReady/ACK
  proto.rs           envelope + framing (escape '+'/'|', delimiter '|') + tests
  keymap.rs          Windows VK <-> Linux evdev KEY_* tables (from keycodes.json)
  backend/
    mod.rs           Backend trait + types + detect() (Wayland or stub, composed with AT-SPI)
    wayland.rs       injection + clipboard + selection
    uinput.rs        in-process /dev/uinput virtual keyboard + held-modifier wait
    wl_clipboard.rs  in-process text/plain+text/html clipboard (ext_data_control)
    atspi_app.rs     AT-SPI active-app tracker + AppInfoUpdate focus events
    atspi_sel.rs     AT-SPI selection read for GetSelectedTextViaCopy
    stub.rs          no-op fallback (keeps handshake alive without uinput)
  capture/
    mod.rs           KeypressEvent emission + HeldKeys (CheckStaleKeys)
    evdev.rs         /dev/input reader, one thread per keyboard
```

## Legal

Clean-room reimplementation against a recovered IPC contract; ships no Wispr Flow
proprietary code, and is released into the public domain under the
[Unlicense](UNLICENSE). The app itself remains under its own terms; see the
[legal posture](https://github.com/wispr-flow-linux/wispr-flow-linux#legal-posture)
in the main repo.
