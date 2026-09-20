# Tests

Four tiers, fastest first. CI (`.github/workflows/capsule-tests.yml` and
`helper.yml`, on Blacksmith runners) runs the first three on every push.

## 1. bats unit tests (no build needed)

Pure-shell tests of the launcher library, the diagnostics and the patch
scripts. No artifact, no display, no root.

```bash
bats tests/*.bats          # or: npx --yes bats tests/*.bats
```

| File | Covers |
|------|--------|
| `launcher-common.bats` | `scripts/launcher-common.sh`: logging paths, `check_display`, `build_electron_args` (Wayland-only, plugin socket gate, GPU flag, exports), `setup_electron_env`, `cleanup_stale_lock`, `wispr_config_dir`. |
| `doctor.bats` | `scripts/doctor.sh`: the `_pass`/`_fail`/`_warn` counter, display / Flow Bar socket / clipboard / helper / singleton-lock checks (driven with stubbed tool presence and temp fixtures), and `run_doctor` exit status. |
| `verify-patches.bats` | `scripts/verify-patches.sh`: PASS when every Linux patch marker is present in a fixture app.asar, exit 1 when any one is omitted (omit-one matrix), exit 2 on bad usage. |
| `linux-patches.bats` | The renderer, window-frame, Windows-behavior, deep-link, tray-click, background-launch and native Flow Bar patches in `scripts/patches/`: each is applied to a hermetic minified-JS fixture carrying its anchor. Tests assert the transformation and marker, preserve unrelated sites, parse the result with Node, check idempotence, and require a non-zero exit when an anchor is absent. |
| `flowbar-model.bats` | `omarchy/plugins/wispr.flowbar/FlowBarModel.js`, driven with node: the status → capsule-state reducer, level smoothing, i18n `{key}` / `custom` notification texts, and the `notification:callback` payload. |
| `extract-flowbar-strings.bats` | `scripts/extract-flowbar-strings.sh`: decodes the status renderer's English string table into JSON, fails on a bundle without the table, exit 2 on bad usage. |

## 2. Node and QML tests

```bash
node --test tests/*.test.cjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
```

The Node tests cover the socket bridge's reconnect logic and the background
launch patch. The QML tests drive `GlassCapsule` offscreen: geometry, the
snapshot gate, entrance and exit motion, the processing clock, buttons and
bounded messages. They exercise the fallback material, not the lens (which
needs a compositor).

## 3. Helper tests

```bash
cd helper && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

## 4. Artifact test (inspects a built AppImage)

```bash
tests/test-artifact-appimage.sh build-linux/appimage
```

Inspection only on a normal machine: file placement inside the AppDir, the
helper binary, the udev rule text, the desktop file and icons, the launcher
script content, and the patch markers in `app.asar` via
`scripts/verify-patches.sh`. The install-and-smoke tier runs only as root with
`WISPR_ARTIFACT_INSTALL=1` (CI containers) and is skipped with a message
otherwise, so the script never installs anything on a dev machine.

## Manual checks on the desktop

The preview harness and the live checks for the glass capsule are described in
[docs/glass-capsule.md](../docs/glass-capsule.md); the measured results are in
[docs/glass-validation.md](../docs/glass-validation.md).
