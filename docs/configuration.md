[< Back to docs index](index.md)

# Configuration

Here's everything you can tune: the runtime environment variables, where state
lives, and the system permissions the text-injection helper needs.

```bash
# Confirm your system is set up for text injection:
wispr-flow --doctor
```

## Environment variables

The launcher (`scripts/launcher-common.sh`) reads `WISPR_*` overrides. I kept
that list short on purpose. The launcher only carries the overrides Wispr Flow
actually needs at runtime. It does **not** carry the menu-bar, titlebar, or
input-method overrides the claude-desktop reference had.

| Variable | Default | Description |
|---|---|---|
| `WISPR_USE_WAYLAND` | unset | Set to `1` to force native Wayland (Ozone): pins `--ozone-platform=wayland`, enables the Wayland IME path, and exports `GDK_BACKEND=wayland`. The default on a Wayland session is XWayland so the Flow Bar patch can move and resize its cropped OS surface reliably. |
| `WISPR_DISABLE_GPU` | unset | Set to `1` to pass `--disable-gpu --disable-software-rasterizer`. Workaround for blank windows / GPU-process crashes on broken drivers or remote sessions. Also applied automatically inside XRDP sessions. |
| `WISPR_NATIVE_FLOWBAR` | auto | `1` forces, `0` disables the native Flow Bar mode. Unset, the launcher enables it when `$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock` exists (the omarchy-shell plugin is running): Electron then runs on native Wayland and the shell draws the Flow Bar. See [Native Flow Bar on Omarchy](#native-flow-bar-on-omarchy). |

```bash
# One-off:
WISPR_USE_WAYLAND=1 wispr-flow
WISPR_DISABLE_GPU=1 wispr-flow

# Persistent:
echo 'export WISPR_DISABLE_GPU=1' >> ~/.profile
```

> [!IMPORTANT]
> `WISPR_USE_WAYLAND=1` is a diagnostic escape hatch. Electron 42 cannot apply
> partial mouse-input regions to the transparent Flow Bar window on native
> Wayland. The Linux patch instead maps a tightly cropped XWayland surface only
> around visible UI and unmaps it while idle. This does not change Wispr Flow's
> `/dev/uinput`, `/dev/input`, or `wl-clipboard` integration. See
> [learnings/wayland-injection.md](learnings/wayland-injection.md).

## Idle Flow Bar behavior

The Linux patch leaves the status window completely unmapped while idle. It
maps only a small surface around the visible bar while the dictation shortcut
is recording or processing, then unmaps it again. A notification temporarily
maps a tightly cropped, focusable surface so its buttons and close control can
be clicked; dismissing it unmaps the surface.

## Where state lives

| Path | Contents |
|---|---|
| `~/.config/Wispr Flow/` | Electron app config + state (the productName is `Wispr Flow`, so the config dir has a space). Includes `SingletonLock`. |
| `~/.cache/wispr-flow/launcher.log` | Launcher log — display backend, GPU decision, session env block, stale-lock cleanup. Attach this to bug reports. |

```bash
# Watch the launcher log:
tail -f ~/.cache/wispr-flow/launcher.log
```

## Text injection: `/dev/uinput` access

Keystroke injection (and clipboard-based paste) writes evdev events to an
in-process `/dev/uinput` virtual keyboard. On stock images that device is
**root-only**. So the packages ship a udev rule, and it grants access two ways
for cross-distro coverage:

```
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
```

- **`TAG+="uaccess"`** — logind grants the active-session user an ACL
  (`user:<you>:rw-`). Works on Fedora and most systemd distros.
- **`GROUP="input", MODE="0660"`** — fallback for distros (e.g. Arch) where
  uinput is a seatless static node logind won't ACL. Requires the user to be in
  the **`input` group**.

```bash
# Add yourself to the input group (then log out / back in):
sudo usermod -aG input "$USER"

# Immediate grant for the current session (no relogin):
sudo setfacl -m u:$USER:rw /dev/uinput
```

If `/dev/uinput` is missing entirely, the `uinput` kernel module isn't loaded.
Run `sudo modprobe uinput` (and make sure it loads at boot). I let
`wispr-flow --doctor` check all of this for you, and it prints the exact fix.

## Clipboard tools

Clipboard-based paste and selection reads shell out to clipboard CLIs:

| Session | Required | Package |
|---|---|---|
| Wayland | `wl-copy` / `wl-paste` | `wl-clipboard` |
| X11 | `xclip` **or** `xsel` | `xclip` / `xsel` |

On Wayland, `wl-clipboard` is a **hard runtime dependency**, and the packages
declare it. I hit this on the stock Ubuntu image. It was missing there, and
paste and selection both failed until I installed it. Install it if `--doctor`
flags it.

## GNOME Shell extension

On GNOME, active-app identity, the running-apps list, and focus events come from
a bundled GNOME Shell extension
(`wispr-flow-window-bridge@wispr.flow`) that bridges
`org.gnome.Shell.Introspect`. (KDE uses an in-process KWin script. wlroots
compositors fall back to AT-SPI. Neither one needs this extension.)

> [!IMPORTANT]
> **GNOME scans extensions only at session start.** After install, you must
> **log out and back in** for the extension to load. The first run after install
> falls back to AT-SPI and logs a "log out and back in" notice; the bridge is
> persistent afterward.

```bash
# Check / enable on GNOME:
gnome-extensions info wispr-flow-window-bridge@wispr.flow
gnome-extensions enable wispr-flow-window-bridge@wispr.flow
# then log out and back in
```

Details and the focus-fallback behavior:
[learnings/gnome-shell-extension.md](learnings/gnome-shell-extension.md).

## AT-SPI accessibility

Selection reads (`GetSelectedTextViaCopy`) and the universal active-app provider
for non-KDE/GNOME Wayland compositors (Sway, Hyprland) use the AT-SPI2
accessibility bus. The helper calls `set_session_accessibility(true)`
(idempotent, best-effort) so toolkits expose their accessible trees, and on the
tested images the AT-SPI registry autostarts on demand. Some apps don't ship an
a11y bridge: bare terminals, a few Electron apps. Those won't resolve. That's
expected, and only those windows degrade to empty.

`wispr-flow --doctor` reports the AT-SPI state
(`toolkit-accessibility` / `org.a11y.Bus` reachability).

## Diagnostics

When something isn't working, start here. `wispr-flow --doctor` checks the
display server, `/dev/uinput` writability, `input` group membership, clipboard
tools, AT-SPI, the GNOME extension (on GNOME), the helper binary, the singleton
lock, and recent crashes. For reading its output, see
[troubleshooting.md](troubleshooting.md).

## Native Flow Bar on Omarchy

On Omarchy the Flow Bar can be drawn by an omarchy-shell (Quickshell) plugin
as a layer-shell surface instead of Electron's XWayland window, which lets the
app run on native Wayland: the Hub becomes a normal managed window with
per-monitor scaling and the bar is anchored, click-through and themed.
Notifications go through the desktop notification daemon (top-right toasts,
history, do-not-disturb all apply); clicking a toast runs the notification's
primary action, closing it dismisses.

```bash
scripts/omarchy/install-flowbar-plugin.sh      # link + enable wispr.flowbar
wispr-flow                                     # launcher detects the socket
scripts/omarchy/install-flowbar-plugin.sh --uninstall
```

How it fits together:

- `omarchy/plugins/wispr.flowbar/` (plugin) serves
  `$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock`.
- `scripts/patches/linux-native-flowbar.sh` (main bundle) mirrors every
  `status:*` / `notification:*` IPC message to that socket as JSON lines,
  accepts `status:startClicked|stopClicked|cancelClicked` and
  `notification:callback` back, and never maps the Electron status window.
  The hidden status renderer keeps owning microphone capture.
- `scripts/extract-flowbar-strings.sh` (build) ships the renderer's English
  string table as `resources/flowbar-strings.en.json` so i18n `{key}`
  notification texts render natively.
- The launcher switches to `--ozone-platform=wayland` when the socket exists;
  `WISPR_NATIVE_FLOWBAR=0` restores the XWayland mode.

Scripted checks (the plugin exposes an IPC target):

```bash
omarchy-shell wisprflowbar inject '{"t":"status:audioLevel","p":0.7}'
omarchy-shell wisprflowbar press status:stopClicked
omarchy-shell wisprflowbar state
```
