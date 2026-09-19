# Glass capsule validation — 2026-09-19

The supported implementation uses Qt Quick primitives, static highlights and
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
The recording renderer/helper implementation was retained. Applying the package
and plugin to the user's running desktop is a separate activation step.

See [material configuration and reproducible checks](glass-capsule.md).
