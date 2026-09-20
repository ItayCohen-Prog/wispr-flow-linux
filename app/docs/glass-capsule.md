# Native liquid glass capsule

The Omarchy Flow Bar uses one Qt Quick capsule for listening, processing and
messages. The Hub is unchanged. Recording starts immediately; presentation
animations never gate microphone capture or the helper.

The Arch launcher starts `wispr-flow --background`. After onboarding, opening
it again leaves the Hub closed. `wispr-flow --show-hub` opens the Hub; the desktop
entry also has an **Open Wispr Flow** action. First-run onboarding, quit requests
and `wispr-flow:` sign-in links keep working.

## Material

The capsule is liquid glass in the sense Apple describes it: it lenses the
content behind it rather than scattering it. The model, in
`omarchy/plugins/wispr.flowbar/shaders/lens.frag`, follows the open-source
reconstructions that were checked against pixel measurements of iOS 26 glass:

- **Backdrop.** `GlassBackdrop.qml` takes one frame of the desktop under the
  layer through `ScreencopyView` and blurs it once (four single-texel Gaussian
  passes at half resolution, about 7 px sigma). Nothing is captured while the
  capsule is hidden.
- **Lens.** A squircle bevel across a 14 px rim band gives each pixel a surface
  slope; exact Snell refraction (index 1.5) turns it into a displacement that
  shows compressed exterior at the rim, plus a 3 % magnification of the interior.
  The semicircular caps get a wider band, so their roundness reads. Red and blue
  are displaced slightly less and more than green.
- **Adaptive tint.** The mean luminance under the capsule picks light glass
  (near white at 30 %) or dark glass (0x37 at 36 %) for the whole element, never
  per pixel. Text, glyphs and the level meter flip with it.
- **Light.** A key light from the top left draws a 1-2 px edge line and a soft
  rim highlight; a weaker counter light does the same on the opposite edge. A
  faint dark step marks the sides, and a soft shadow sits below.
- **Motion.** The glass forms from a droplet with a spring that overshoots
  slightly, its lens thicker while forming, and pulls back into a drop when it
  leaves. Width and height use interruptible springs for messages. Content
  fades with the glass. Only processing runs a 30 Hz timer.

Glyphs sit directly on the glass with no chrome of their own (`GlassIcon.qml`,
`GlassIconButton.qml`); hovering lifts a soft disc of light under them. Text
actions in a message are plain capsules (`GlassButton.qml`), because Apple keeps
glass off glass.

### Why a snapshot

A Wayland layer cannot see through itself. A live capture of the output
includes the capsule from the previous frame, so it would refract itself.
Hyprland's `no_screen_share` rule does not exclude the layer either: it paints
the layer as a black box in every screencopy frame. The snapshot is taken the
instant before the glass forms (the layer maps transparent so the compositor
commits a frame; the frame arrives in 10-15 ms) and a new one is taken on
every show. What changes under the capsule while it is visible is not reflected
until it appears next.

No compositor blur is needed. Load
[`omarchy/hyprland-flowbar.lua`](../omarchy/hyprland-flowbar.lua) to skip
Hyprland's own layer fade, which would fight the capsule's entrance:

```lua
hl.layer_rule({ match = { namespace = "^wispr-flowbar$" }, no_anim = true, blur = false })
```

Set these in the **omarchy-shell process environment**, then reload that shell:

- `WISPR_FLOWBAR_REDUCED_MOTION=1`: immediate geometry and a stationary
  processing indicator.
- `WISPR_FLOWBAR_MATERIAL=solid`: a plain tinted capsule without the snapshot.
  Software rendering, and any run without a ready snapshot after 150 ms, use
  the same fallback.

Compositor plugins are optional experiments, not runtime dependencies. Both
[hyprglass](https://github.com/hyprnux/hyprglass) and
[hyprliquid](https://github.com/Neuron-Group/hyprliquid) support layers, but depend
on Hyprland internals and can break across compositor updates.

See the [measured validation and its limits](glass-validation.md).

## Preview and checks

Run the preview in a real Hyprland session; it binds a real socket and creates
the real overlay, and the glass needs a compositor to snapshot. A unique socket
keeps it separate from the user's app.

```bash
WISPR_FLOWBAR_SOCKET="$XDG_RUNTIME_DIR/wispr-preview.sock" \
  quickshell -p omarchy/preview.qml
```

Preview controls send synthetic status and notification events. Their callback
response appears in the preview. The editable field checks keyboard focus.
`WISPR_FLOWBAR_TEST_PATTERN=1` adds a static striped background so the lens and
frost are easy to judge. This preview does not record audio or contact a
dictation service.

```bash
node --test tests/background-launch.test.cjs tests/native-flowbar.test.cjs
bats tests/*.bats
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
python tests/flowbar-integration.py --config omarchy/preview.qml \
  --socket "$XDG_RUNTIME_DIR/wispr-preview.sock"
```

The QML tests run without a compositor, so they exercise the fallback material
and the capsule's geometry, gating and motion, not the lens.

For CPU/RSS sampling, use `tests/flowbar-benchmark.py --help` with the explicit
PIDs and socket of the preview. It reports CPU as a percentage of one logical
core. It does not measure GPU energy or isolate Qt from the preview.

The QML plugin remains separate from the proprietary AppImage. Install it with
`scripts/omarchy/install-flowbar-plugin.sh --reload`, following the main README.
`--uninstall` removes the plugin link; restart Wispr to return to its Electron
overlay.

## Editing the shaders

The committed `.qsb` files are compiled for Qt 6.4 compatibility and need no
build tool on the user's machine. After editing a GLSL source, rebuild it:

```bash
for f in lens blur; do
  /usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 \
    -o omarchy/plugins/wispr.flowbar/shaders/$f.frag.qsb \
    omarchy/plugins/wispr.flowbar/shaders/$f.frag
done
```

`lens.frag` keeps its tuning as constants at the top (band width, rim shift,
index, dispersion, bevel width); `GlassSurface.qml` passes the per-state inputs
(shape, form, tint, frost, emphasis).

## Updating a running shell

A plugin rescan can leave QML component types cached in the existing engine. Use
`install-flowbar-plugin.sh --reload` to restart the shell and verify the runtime
version, rather than checking only the files or socket. The read-only command
`omarchy-shell wisprflowbar version` must report the installed manifest version.
