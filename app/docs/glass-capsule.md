# Native glass capsule

The Omarchy Flow Bar uses one Qt Quick capsule for listening, processing and
messages. The Hub is unchanged. Recording starts immediately; presentation
animations never gate microphone capture or the helper.

The Arch launcher starts `wispr-flow --background`. After onboarding, opening
it again leaves the Hub closed. `wispr-flow --show-hub` opens the Hub; the desktop
entry also has an **Open Wispr Flow** action. First-run onboarding, quit requests
and `wispr-flow:` sign-in links keep working.

## Material and motion

The default material is a dark, readable glass approximation with static rim
highlights. It needs no blur setting, shader or compositor plugin. Width and
height use interruptible springs; the waveform follows microphone levels.
Only processing runs a continuous animation. Hidden and inactive-monitor
capsules stop that animation. Errors can appear after dictation finishes, retain
upstream callback IDs, pause their timeout while hovered, and scroll when they
exceed the available screen height.

Set these in the **omarchy-shell process environment**, then reload that shell:

- `WISPR_FLOWBAR_REDUCED_MOTION=1`: immediate geometry and a stationary processing
  indicator.
- `WISPR_FLOWBAR_MATERIAL=frosted`: translucent material for compositor blur.
  Without blur this exposes sharp background content, reducing readability.

For Hyprland 0.56 Lua configuration, the frosted material requires:

```lua
hl.config({ decoration = { blur = { enabled = true, size = 3, passes = 2 } } })
hl.layer_rule({
  match = { namespace = "^wispr-flowbar$" },
  blur = true,
  ignore_alpha = 0.05,
  no_anim = true,
})
```

`ignore_alpha` keeps the transparent area surrounding the capsule clear.
Enabling blur globally can also change other translucent windows and layers.
The installer does not silently make that desktop-wide change. Leave blur off
and use the default material when minimum overhead is the priority.

Compositor plugins are optional experiments, not runtime dependencies. Both
[hyprglass](https://github.com/hyprnux/hyprglass) and
[hyprliquid](https://github.com/Neuron-Group/hyprliquid) support layers, but depend
on Hyprland internals and can break across compositor updates. Qt's
[ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html) alone cannot
sample and refract other applications behind a Wayland surface.

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
then reload the shell when convenient. `--uninstall` removes the plugin link;
restart Wispr to return to its Electron overlay.
