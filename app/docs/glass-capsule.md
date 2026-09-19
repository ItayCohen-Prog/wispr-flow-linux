# Native glass capsule

The Omarchy Flow Bar uses one Qt Quick capsule for listening, processing and
messages. The Hub is unchanged. Recording starts immediately; presentation
animations never gate microphone capture or the helper.

The Arch launcher starts `wispr-flow --background`. After onboarding, opening
it again leaves the Hub closed. `wispr-flow --show-hub` opens the Hub; the desktop
entry also has an **Open Wispr Flow** action. First-run onboarding, quit requests
and `wispr-flow:` sign-in links keep working.

## Material and motion

The capsule has a frosted grey body, a rounded bevel, a polished rim, an inset
shadow and glass buttons. One small analytic fragment shader draws each material
without sampling the desktop or allocating an offscreen texture. The shader is
static. Width and height use interruptible springs; microphone levels drive the
listening meter. Only processing runs a 30 Hz timer, which stops when hidden or
on an inactive monitor. Notifications keep their original action callbacks.

Real frosting requires compositor blur. A shader in a Wayland client cannot
sample another application's pixels. Without that compositor setting, the body
is transparent and background text remains sharp.

Set these in the **omarchy-shell process environment**, then reload that shell:

- `WISPR_FLOWBAR_REDUCED_MOTION=1`: immediate geometry and a stationary processing
  indicator.
- `WISPR_FLOWBAR_MATERIAL=solid`: an opaque fallback when blur is unavailable.
  Software rendering also has a simple, readable fallback.

For Hyprland 0.56 Lua configuration on stock Omarchy, load
[`omarchy/hyprland-glass-only.lua`](../omarchy/hyprland-glass-only.lua) after other
window and layer rules. This preset enables blur, keeps **all other windows and
layers unblurred**, and enables it for `wispr-flowbar` only. It is intended for a
desktop whose blur was previously disabled. The broad exclusion rules also
suppress other blur preferences until this preset is removed; do not use it on
a desktop where you already want blur elsewhere.

If your desktop already uses blur, keep its settings and add only:

```lua
hl.layer_rule({
  match = { namespace = "^wispr-flowbar$" },
  blur = true,
  ignore_alpha = 0.2,
  xray = false,
  no_anim = true,
})
```

The alpha cutoff excludes the material's soft shadow. The layer follows the
capsule's width and height instead of allocating a monitor-wide strip. The preset
uses size 6, two blur passes and no wallpaper-only xray blur. The plugin installer
does not change compositor settings automatically.

Compositor plugins are optional experiments, not runtime dependencies. Both
[hyprglass](https://github.com/hyprnux/hyprglass) and
[hyprliquid](https://github.com/Neuron-Group/hyprliquid) support layers, but depend
on Hyprland internals and can break across compositor updates. Qt's
[ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html) alone cannot
sample and refract other applications behind a Wayland surface.

See the [measured validation and its limits](glass-validation.md).

## Preview and checks

Run the preview in a disposable Hyprland session; it binds a real socket and
creates the real overlay. A unique socket keeps it separate from the user's app.

```bash
WISPR_FLOWBAR_SOCKET="$XDG_RUNTIME_DIR/wispr-preview.sock" \
  quickshell -p omarchy/preview.qml
```

Preview controls send synthetic status and notification events. Their callback
response appears in the preview. The editable field checks keyboard focus.
`WISPR_FLOWBAR_TEST_PATTERN=1` adds a static striped background for blur comparison.
This preview does not record audio or contact a dictation service.

```bash
node --test tests/background-launch.test.cjs tests/native-flowbar.test.cjs
bats tests/*.bats
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
python tests/flowbar-integration.py --config omarchy/preview.qml \
  --socket "$XDG_RUNTIME_DIR/wispr-preview.sock"
```

The integration test requires the preview and `hyprctl` to address the same
isolated compositor. It checks actual layer creation/removal across repeated
opens, notification expiry and malformed-message recovery.

For CPU/RSS sampling, use `tests/flowbar-benchmark.py --help` with the explicit
PIDs and socket of the disposable preview. It reports CPU as a percentage of
one logical core. It does not measure GPU energy or isolate Qt from the preview.

The QML plugin remains separate from the proprietary AppImage. Install it with
`scripts/omarchy/install-flowbar-plugin.sh`, following the main README. To roll
back, install the previous Arch package and restore the previous plugin revision,
then reload the shell when convenient. Remove the loaded glass-only Lua preset
to restore the previous compositor blur policy. `--uninstall` removes the plugin link;
restart Wispr to return to its Electron overlay.

## Editing the material

The committed `glass.frag.qsb` is compiled for Qt 6.4 compatibility and needs no
build tool on the user's machine. After editing the GLSL source, rebuild it with:

```bash
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 \
  -o omarchy/plugins/wispr.flowbar/shaders/glass.frag.qsb \
  omarchy/plugins/wispr.flowbar/shaders/glass.frag
```

`qml omarchy/material-preview.qml` shows the actual capsule over grey, colourful
and dark backdrops. Its Qt backdrop blur is **preview-only**, not a substitute
for the native layer test. It requires Qt Quick Effects. The native preview also
accepts `WISPR_FLOWBAR_PREVIEW_SCENE=grey` or `colour`.
