# Glass capsule validation

## Liquid glass revision, 2026-09-20

Before this revision two capture designs were tried on the real desktop
(Hyprland 0.56.2, Quickshell 0.3.1, NVIDIA RTX 4070 Laptop, 1920x1080 at 1x
and 2560x1600 at 1.6x):

- A live `ScreencopyView` of the output under the layer: the capsule saw
  itself from the previous frame (recursive image). Cost while visible was
  about 3 % of a core for the overlay plus 1.6 % for Hyprland.
- The same with a `no_screen_share` layer rule: Hyprland renders the layer as
  a black box in every screencopy frame (verified with `grim`), so nothing
  behind the capsule is visible to it.

The shipped design captures one frame before the layer forms. Measured from
the socket message that shows the capsule: the frame arrived after 10-14 ms and
the adaptive luminance after 26-30 ms, on three consecutive shows. The capture
session ends when the capsule hides.

Ten-second samples of the preview instance and the compositor together, as a
percent of one logical core, with the plugin on the 1920x1080 output:

| State | Preview | Hyprland |
| --- | ---: | ---: |
| Hidden | 0.0 % | 0.2-0.5 % (desktop baseline) |
| Listening, level updates at 20 Hz | 2.6 % | 3.2 % |
| Processing | 2.4 % | 3.0 % |

GPU utilisation reported by `nvidia-smi` stayed at 0-5 %. These are short CPU
samples, not power measurements. The recording of the entrance (60 fps) shows
the droplet reaching the pill in about 200 ms with a small overshoot; the exit
takes about 270 ms. Eleven QML behaviour tests and the four Node regression
tests pass offscreen.


## Runtime reload and opening fix, 2026-09-20

The earlier activation check was insufficient: the on-disk plugin and socket
were current, but Omarchy's existing QML engine still displayed the old material.
A new runtime-version IPC call remained unavailable after a plugin rescan and
became available after a full shell restart. Updates now support `--reload` and
verify the running version, not only the socket.

The updated material was then captured on the actual laptop display at 160%
scale. Opening animation resized the layer window every frame, producing visible
position jumps. The backing width is now fixed at 404 logical pixels, including
padding; recording uses a 94-pixel height. The window grows only for messages
and holds that allocation until hidden. Capsule animation stays inside it.
Normal entry preserves control geometry and uses a short fade/scale transition.

Three 60 fps recording-open captures before the window fix showed 32 lower-edge
jumps greater than two physical pixels. Three captures after the correction
showed none under the same detection threshold. These are local visual regression
measurements, not an FPS or energy benchmark. Nine QML behavior tests passed,
including entry geometry and stable message-layout targets.


## Material revision, 2026-09-20

The first installed pill was too flat and transparent. It has been replaced with
a frosted body, broad illuminated bevels, inset shading and glass buttons, checked
against the supplied grey and colourful references. The material is one static
analytic shader per shape; it does not read the desktop. Hyprland supplies the
actual backdrop blur. The layer now measures 224 x 94 logical pixels in recording
mode, including padding, rather than spanning the monitor.

The revised native overlay was rendered on Hyprland 0.56.2 / Qt 6.11.2 inside an
isolated desktop at 1024 x 768. Fourteen real layer lifecycle and size checks,
seven QML behavior tests and four Node regression tests passed. A six-second capture of
processing contained 170 distinct frames out of 180, with 27-29 distinct frames
in every second. Computer use checked the recording and notification controls.

The scoped blur preset was checked with a translucent window over stripes. Its
captures with global blur enabled and disabled were byte-identical. A positive
control that allowed blur on that window visibly softened the stripes and
produced a different capture. The Wispr capsule itself softened the stripes;
the shadow and surrounding area stayed clear.

Ten-second samples after settling, preview and compositor combined, as a percent
of one logical core:

| Revised material | Hidden | Stationary notification | Listening | Processing |
| --- | ---: | ---: | ---: | ---: |
| With scoped blur | 0.00% | 0.00% | 2.20% | 1.70% |
| Same material, blur disabled | 0.00% | 0.00% | 1.90% | 1.50% |

The standalone Qt preview used approximately 182-186 MiB RSS, including its demo
window, Qt runtime and rendering resources. This is not the incremental memory
usage of the plugin in Omarchy. These are short CPU samples, not GPU power or
battery measurements. Zero measured CPU ticks is not a zero-overhead guarantee.
Do not compare these timings directly to the earlier run below: the layer size,
preview dimensions and material have changed.

## Earlier implementation, 2026-09-19

The following results describe the first material, before the visual correction.
They are retained as historical evidence, not a claim about the revised look.

That implementation used Qt Quick primitives, static highlights and
short spring transitions. Its processing meter updates at 30 Hz and stops when
hidden. Real compositor blur is optional. Refraction plugins are not required.

## Environment and scope

Wispr 1.6.7, Qt 6.11.2, Quickshell 0.3.1, Hyprland 0.56.2, NVIDIA RTX 4070 Laptop.
Tests ran in a private desktop with a nested Hyprland compositor. The laboratory
needed temporary Cage/Aquamarine fixes for the nested xdg-shell configure/ack
sequence. Those fixes and neither glass plugin are shipped or installed on the
user's desktop. This is not a battery-life or whole-machine GPU benchmark.

The default material, native blur (size 3, two passes), hyprglass (subtle preset,
alpha threshold 0.05, namespace only, live resampling off) and hyprliquid (layer
Liquid Glass, VDF mode 1, onchange) were rendered and exercised. Both plugins
compiled and loaded against the installed compositor headers. Layer appearance
was checked against a striped background.

## CPU samples

Single 10-second steady-state samples after a two-second settling period.
Listening receives 30 synthetic microphone updates per second. Values below sum
the **preview/Qt process and nested compositor**, expressed as percent of **one
logical core**, not percent of the entire machine.

| Material | Hidden | Listening | Processing |
| --- | ---: | ---: | ---: |
| Default, blur disabled | 0.00% | 5.89% | 5.79% |
| Native frosted blur | 0.20% | 6.19% | 6.28% |
| hyprglass | 0.00% | 5.79% | 5.40% |
| hyprliquid | 0.00% | 8.89% | 6.90% |

These small samples do not establish a reliable speed ranking. The native
implementation was selected for readability, bounded animation work and avoiding
private compositor hooks. Plugin GPU costs, energy use and frame pacing under
heavy desktop load remain unmeasured. A zero CPU sample means no measurable
process CPU ticks in that interval, not a guarantee of zero resource use.

The standalone preview/Qt process used roughly 177–210 MiB RSS across the runs.
That includes Qt, the demo window and rendering buffers. It is **not** the added
memory cost of loading this component into the already-running Omarchy shell.

A six-second 30 fps X11 capture of the final processing meter contained 177
distinct cropped frames out of 180, with motion throughout the capture. Earlier
NumberAnimation-driven processing stalled in this nested environment; that
implementation and its processing samples were discarded. The final samples
above use the bounded timer.

## Functional evidence

- 120 BATS checks passed; four Node patch behavior tests passed.
- Seven QML behavior tests passed: lifecycle, interrupted transitions, controls,
  bounded messages, processing motion and inactive-monitor behavior.
- Eleven real layer-shell integration checks passed, including three open/close
  cycles, notification-only visibility, expiry and malformed-message recovery.
- Computer use verified recording controls, notification action payloads,
  click-through input outside the capsule and keyboard focus after an action.
- The rebuilt AppImage passed 33 artifact checks. The optional Xvfb smoke check
  skipped because Xvfb was unavailable. A separate actual desktop launch of the
  AppImage in extract-and-run mode reached helper-ready without opening a Hub;
  `--show-hub` opened it. First-run onboarding also remained visible as intended.
- Shellcheck and shell syntax checks passed. The public repository has a root CI
  workflow for patch/reducer/QML checks on Ubuntu 24.04.

Microphone input, account authentication, transcription quality and injection
into a real user's application were not tested with the disposable profile.
The recording renderer/helper implementation was retained. The package and first
plugin were subsequently activated on the user's desktop;
this did not establish a visual match to the reference.

See [material configuration and reproducible checks](glass-capsule.md).
