[< Back to docs index](index.md)

# Configuration

Everything you can tune: the launcher's environment variables, where state
lives, and the system access the text-injection helper needs.

```bash
# Confirm your system is set up:
wispr-flow --doctor
```

## Environment variables

The launcher (`scripts/launcher-common.sh`, shipped inside the AppImage as
`AppRun`) reads two `WISPR_*` overrides. Everything else is decided for you:
the app runs on native Wayland and the omarchy-shell plugin draws the Flow Bar.

| Variable | Default | Description |
|---|---|---|
| `WISPR_NATIVE_FLOWBAR` | unset | Set to `1` to start even when the plugin's socket at `$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock` is missing (development). Normally the launcher refuses to start without the socket and says so. |
| `WISPR_DISABLE_GPU` | unset | Set to `1` to pass `--disable-gpu --disable-software-rasterizer`. Workaround for blank windows or GPU-process crashes on broken drivers. |

```bash
# One-off:
WISPR_DISABLE_GPU=1 wispr-flow

# Persistent:
echo 'export WISPR_DISABLE_GPU=1' >> ~/.profile
```

The omarchy-shell plugin reads its own variables from the **shell's**
environment (reload the shell after changing them):
`WISPR_FLOWBAR_REDUCED_MOTION=1` and `WISPR_FLOWBAR_MATERIAL=solid`. See
[glass-capsule.md](glass-capsule.md).

## Where state lives

| Path | Contents |
|---|---|
| `~/.config/Wispr Flow/` | Electron app config and state (the productName is `Wispr Flow`, so the config dir has a space). Includes `SingletonLock`. |
| `~/.cache/wispr-flow/launcher.log` | Launcher log: session env block, GPU decision, why a launch was refused, stale-lock cleanup. Attach this to bug reports. |

```bash
tail -f ~/.cache/wispr-flow/launcher.log
```

## Text injection: `/dev/uinput` access

Keystroke injection (and clipboard-based paste) writes evdev events to an
in-process `/dev/uinput` virtual keyboard, and push-to-talk reads
`/dev/input/event*`. Both are root-only on a stock image. Once, after the
first install:

```bash
wispr-flow --install-udev-rules
```

installs this rule and reloads udev:

```
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess", GROUP="input", MODE="0660"
```

`TAG+="uaccess"` lets logind grant the active-session user an ACL. On Arch
uinput is a seatless static node that logind will not ACL, so the
`GROUP="input"` half applies and you need to be in the **`input` group**:

```bash
sudo usermod -aG input "$USER"        # then log out and back in
sudo setfacl -m u:$USER:rw /dev/uinput  # immediate grant for this session only
```

If `/dev/uinput` is missing entirely, load the module: `sudo modprobe uinput`.
`wispr-flow --doctor` checks all of this and prints the exact fix.

## Clipboard tools

Clipboard paste and selection reads shell out to `wl-copy` / `wl-paste`
(package `wl-clipboard`). It is a hard runtime dependency; `--doctor` flags it.

## AT-SPI accessibility

The helper learns which app is focused, lists running apps and reads selected
text through the AT-SPI2 accessibility bus (`org.a11y.Bus`), which any Wayland
compositor can host. The helper turns `toolkit-accessibility` on (idempotent,
best-effort) so toolkits expose their trees. Apps without an a11y bridge (bare
terminals, some Electron apps) come back empty; that is expected, and only
those windows degrade. `--doctor` reports the AT-SPI state.

## Diagnostics

`wispr-flow --doctor` checks the display server, the Flow Bar plugin socket,
`/dev/uinput` writability, `input` group membership, `/dev/input` readability,
`wl-clipboard`, AT-SPI, the helper binary, the singleton lock and recent
crashes. For reading its output, see [troubleshooting.md](troubleshooting.md).

## Native Flow Bar on Omarchy

The Flow Bar is drawn by an omarchy-shell (Quickshell) plugin as a layer-shell
surface. That lets the app run on native Wayland: the Hub is a normal managed
window with per-monitor scaling, and the bar is anchored, click-through and
liquid glass. Notifications from the app render inside the same capsule.

```bash
scripts/omarchy/install-flowbar-plugin.sh --reload   # link, enable, restart the shell, verify
scripts/omarchy/install-flowbar-plugin.sh --uninstall
```

How it fits together:

- `omarchy/plugins/wispr.flowbar/` (plugin) serves
  `$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock` and draws the capsule
  ([glass-capsule.md](glass-capsule.md)).
- `scripts/patches/linux-native-flowbar.sh` (main bundle) mirrors every
  `status:*` / `notification:*` IPC message to that socket as JSON lines,
  accepts `status:startClicked|stopClicked|cancelClicked` and
  `notification:callback` back, and never maps the Electron status window.
  The hidden status renderer keeps owning microphone capture.
- `scripts/extract-flowbar-strings.sh` (build) ships the renderer's English
  string table as `resources/flowbar-strings.en.json` so i18n `{key}`
  notification texts render natively.
- The launcher requires the socket (or `WISPR_NATIVE_FLOWBAR=1`) and starts
  Electron with `--ozone-platform=wayland`.

Scripted checks (the plugin exposes an IPC target):

```bash
omarchy-shell wisprflowbar inject '{"t":"status:dictationStatus","p":"listening"}'
omarchy-shell wisprflowbar inject '{"t":"status:audioLevel","p":0.7}'
omarchy-shell wisprflowbar press status:stopClicked
omarchy-shell wisprflowbar state
```
