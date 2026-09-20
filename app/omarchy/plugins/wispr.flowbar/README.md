# wispr.flowbar

The Omarchy (Quickshell) Flow Bar for Wispr Flow: a liquid glass capsule on a
layer-shell surface, fed by the app over a Unix socket.

```
~/.config/omarchy/plugins/wispr.flowbar -> <repo>/app/omarchy/plugins/wispr.flowbar
$XDG_RUNTIME_DIR/wispr-flow/flowbar.sock   # served by this plugin
```

- The plugin serves the socket; the patched app (`linux-native-flowbar.sh`)
  connects and mirrors its `status:*` / `notification:*` IPC as JSON lines.
- Clicks on the capsule send `status:cancelClicked` / `status:stopClicked`
  back; message actions send `notification:callback`.
- The launcher refuses to start Wispr Flow while this socket is missing.

Install with `scripts/omarchy/install-flowbar-plugin.sh --reload`. The plugin
directory is a symlink into the repo and omarchy-shell does not hot-reload
code behind a symlink, so run the same command after editing. Material notes,
the preview harness and the checks are in `docs/glass-capsule.md`.

Test hooks:

```bash
omarchy-shell wisprflowbar inject '{"t":"status:dictationStatus","p":"listening"}'
omarchy-shell wisprflowbar inject '{"t":"status:audioLevel","p":0.7}'
omarchy-shell wisprflowbar press status:stopClicked
omarchy-shell wisprflowbar state
```
