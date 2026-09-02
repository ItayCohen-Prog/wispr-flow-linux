# wispr.flowbar

Native Omarchy (Quickshell) Flow Bar for Wispr Flow.

```
~/.config/omarchy/plugins/wispr.flowbar -> <repo>/omarchy/plugins/wispr.flowbar
$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock   # served by this plugin
```

- The plugin serves a Unix socket; the patched app (`linux-native-flowbar.sh`)
  connects and mirrors its `status:*` / `notification:*` IPC as JSON lines.
- The launcher switches Electron to native Wayland whenever the socket exists
  (`WISPR_NATIVE_FLOWBAR=0` disables, `=1` forces).
- Clicks on the pill send `status:cancelClicked` / `status:stopClicked` back.

Install: `scripts/omarchy/install-flowbar-plugin.sh`. The plugin directory is a
symlink into the repo; omarchy-shell does not hot-reload code behind a
symlink, so after editing run `omarchy restart shell`. Test hooks:

```bash
omarchy-shell wisprflowbar inject '{"t":"status:dictationStatus","p":"listening"}'
omarchy-shell wisprflowbar inject '{"t":"status:audioLevel","p":0.7}'
omarchy-shell wisprflowbar press status:stopClicked
omarchy-shell wisprflowbar state
```
