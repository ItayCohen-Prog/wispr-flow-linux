# Wispr Flow on Omarchy - Development Notes

This file is read by AI coding tools (`CLAUDE.md` imports it). It is a fast
reference; the documents it links to are the source of truth.

## Required reading

- [`../README.md`](../README.md) — what this is, what it is not, and the
  setup steps as actually run on Omarchy.
- [`docs/reference/ipc-contract.md`](docs/reference/ipc-contract.md) — the IPC
  contract the clean-room helper implements.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — what is accepted, what goes upstream
  to Wispr, the bash and Rust style requirements, the AI-attribution policy.
- [`docs/index.md`](docs/index.md) — entry point for the rest of the docs.
- [`docs/styleguides/bash_styleguide.md`](docs/styleguides/bash_styleguide.md)
  — shell conventions. Tabs, 80 cols, `[[ ]]`, no `set -e`.

## Project overview

An **unofficial** Linux port of the proprietary **Wispr Flow** voice-dictation
app (Electron 42, shipped as a Squirrel Windows installer), targeting **only
Omarchy** (Arch Linux, Hyprland, omarchy-shell). Three parts, one repo:

1. `app/` — the repackaging pipeline: extract the Windows installer, patch the
   minified bundle for Linux, stage a Linux Electron and the prebuilt native
   sqlite modules, and produce an AppImage that `packaging/arch/PKGBUILD`
   installs.
2. `helper/` — the clean-room Rust helper that injects text into the focused
   app over `/dev/uinput`, reads the clipboard over `ext-data-control`,
   captures push-to-talk from evdev, and tracks focus over AT-SPI. Built from
   the documented IPC contract; contains no Wispr Flow code.
3. `app/omarchy/plugins/wispr.flowbar/` — the omarchy-shell (Quickshell)
   plugin that draws the Flow Bar as liquid glass on a layer-shell surface,
   fed by the app over a Unix socket.

Both `app/` and `helper/` were imported from the upstream `wispr-flow-linux`
org with `git subtree` and then cut down to what runs on Omarchy: no deb, rpm
or Nix packaging, no X11/XWayland mode, no GNOME or KDE backends.

## Layout (app/)

- `build.sh` — orchestrator: flags, host detection, dependency check,
  installer download, staging, AppImage packaging. `--test-flags` dry run.
- `scripts/build-linux.sh` — the staging pipeline: extract, patch, stage
  native modules, repack `app.asar`, verify markers.
- `scripts/patches/` — one script per bundle patch (see `scripts/README.md`);
  `verify-patches.sh` greps the repacked asar for every marker.
- `scripts/packaging/appimage.sh` — writes the AppDir, `AppRun` launcher,
  desktop file and icons, then runs `appimagetool`.
- `scripts/launcher-common.sh`, `scripts/doctor.sh` — the runtime launcher
  library and `wispr-flow --doctor`, both shipped inside the AppImage.
- `scripts/omarchy/install-flowbar-plugin.sh` — links and enables the plugin,
  `--reload` restarts the shell and verifies the running version.
- `omarchy/` — the plugin, its preview harness and the Hyprland rule file.
- `tests/` — bats, Node, QML and artifact tests (`tests/README.md`).
- `docs/` — configuration, troubleshooting, glass material notes, decisions,
  learnings, the IPC contract.

## Code style

### Bash

All shell scripts follow the [Bash Style Guide](docs/styleguides/bash_styleguide.md):
tabs, lines under 80 chars (URLs and regexes excepted), `[[ ]]`, `$(...)`,
single quotes for literals, lowercase variables, `local` in functions, **no
`set -e`** (check status explicitly), no `eval`, no backticks. Run `shellcheck`
before pushing; a per-line disable with a why-comment is the last resort.

### Rust

`cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`
in `helper/` must all pass; CI runs them.

### QML and shaders

Plugin files are two-space indented QML. Fragment shaders are GLSL 440
compiled to `.qsb` with `qsb --qt6 --qsbversion 64`; commit both. The QML must
keep working on Qt 6.4 (CI) as well as the Qt 6.11 Omarchy ships, so guard
newer properties.

### Docs and CHANGELOG

One declarative sentence, then a code block or list, at the top of every doc
page. Lowercase kebab-case filenames in `docs/`; order lives in
`docs/index.md`. Troubleshooting headings are the literal symptom.
`CHANGELOG.md` follows Keep a Changelog 1.1.0.

## Learnings

[`docs/learnings/`](docs/learnings/index.md) holds the non-obvious mechanics:
patching minified JS so patches survive re-minification, the platform gates
Linux falls through, the V8 sqlite ABI patch, the launcher rename that
`app.isPackaged` depends on, Wayland injection, the evdev key monitor and the
helper spawn environment. Read the relevant page before touching a subsystem;
add a page when you learn something that would save the next person a day.

## Testing

```bash
cd app
bats tests/*.bats
node --test tests/*.test.cjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
cd ../helper && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

Visual changes to the capsule are checked on the real desktop with the preview
harness in `omarchy/preview.qml` and `grim` screenshots
([docs/glass-capsule.md](docs/glass-capsule.md)).

## GitHub

- Use the `gh` CLI. Reference issues with `#123` / `Fixes #123`.
- CI: `.github/workflows/capsule-tests.yml` (bats, Node, QML, shellcheck) and
  `helper.yml` (fmt, clippy, test), on Blacksmith runners.

### Attribution

For PR descriptions:

```
---
Generated with [Claude Code](https://claude.ai/code)
Co-Authored-By: Claude <model-name> <noreply@anthropic.com>
<XX>% AI / <YY>% Human
Claude: <what AI did>
Human: <what human did>
```

Use the actual model name and keep the split honest. For issues and comments
use `Written by Claude <model-name> via [Claude Code](https://claude.ai/code)`.
Commits carry a `Co-Authored-By` trailer.
