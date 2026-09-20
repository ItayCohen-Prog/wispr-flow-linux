[< Back to docs index](index.md)

# Building from Source

`./build.sh` turns the Wispr Flow Windows installer into the AppImage that
`packaging/arch/PKGBUILD` installs. The setup steps in the
[repository README](../../README.md) run it once; this page is the reference
for what it does and what can go wrong.

```bash
./build.sh --exe "$HOME/Downloads/Wispr Flow Setup-v1.6.7.exe"
```

## Prerequisites

`./build.sh` checks for these and prints the `pacman` line for anything missing;
it installs nothing itself.

| Command | Arch package | Used for |
|---|---|---|
| `7z` | `7zip` | extract the Squirrel `.exe` → `.nupkg` → app payload |
| `curl` | `curl` | download the Linux Electron runtime and the prebuilt native modules |
| `wrestool`, `icotool` | `icoutils` | pull icons out of the Windows resources |
| `convert` | `imagemagick` | icon resize/convert to Linux sizes |
| `rsync` | `rsync` | stage the resources tree |
| `node`, `npx` | `nodejs`, `npm` | `@electron/asar` pack/unpack |
| `python3` | `python` | every patch under `scripts/patches/` |
| `appimagetool` | (not packaged) | `scripts/packaging/appimage.sh`; download it to `~/.local/bin` |
| `cargo` | `rustup` | build the helper first: `cd helper && cargo build --release` |

The helper is staged from `helper/target/release/`; the build refuses to
download the upstream prebuilt helper when that sibling build is missing.

## Obtaining the installer

The build is pinned to Wispr Flow **1.6.7** (`APP_VERSION` in `build.sh`), the
version the patches were verified against. Wispr's "latest" link now serves a
small web installer with no payload, so download the versioned installer and
pass it with `--exe`:

```bash
curl -fL -o ~/Downloads/"Wispr Flow Setup-v1.6.7.exe" \
  "https://dl.wisprflow.com/wispr-flow/win32/x64/Wispr%20Flow%20Setup-v1.6.7.exe"
```

The proprietary installer is never committed. A different installer version
can drift the patch anchors; every patch asserts its anchor and fails the
build rather than silently skipping.

## Flags

| Flag | Values | Meaning |
|---|---|---|
| `-e`, `--exe` | path | Installer .exe to use. Without it the build tries Wispr's endpoint, which currently fails (see above). |
| `--arch` | `amd64` `arm64` | Target architecture (overrides host detection). arm64 is wired through but not hardware-validated. |
| `-c`, `--clean` | `yes` `no` | Remove intermediate build files when done (default `no`). |
| `-r`, `--release-tag` | string | Optional tag embedded in the package version. |
| `--test-flags` | (none) | Parse and print the resolved flags, then exit **without** building. |

`build.sh` is a thin orchestrator over the staging engine
(`scripts/build-linux.sh`) and the AppImage maker
(`scripts/packaging/appimage.sh`). `build-linux/` is wiped at the start of
every run, so copy anything you want to keep out of it.

## How it works

Wispr Flow is an Electron 42 / electron-forge app shipped as a Squirrel Windows
installer. That's the same packaging stack as Claude Desktop, which I maintain a
build script for, so the extract/repack half transfers cleanly. The hard part is
unique to Wispr Flow. Its text-injection "Helper" process exists only as macOS
(Swift) and Windows (C#) binaries, with no Linux variant and no source. A
clean-room Rust helper
([github.com/wispr-flow-linux/helper](https://github.com/wispr-flow-linux/helper))
reimplements it. This build no longer compiles the helper. By default it
auto-fetches the prebuilt binary pinned in `helper-version.txt` and stages it;
set `HELPER_BIN` to use a local build instead (see below). The app bundle is
patched to load it on Linux.

Here's what the staging pipeline (`scripts/build-linux.sh`) does:

1. **Extract** the Squirrel `.exe` with `7z` → `*-full.nupkg` → app payload under
   `lib/net45/` (`resources/app.asar`, native modules, `Release/`, `*.pak`).
2. **Unpack** `app.asar` with `@electron/asar`.
3. **Patch the main bundle.** `scripts/patches/helper-resolver.sh` adds a
   `'linux'` branch to the helper-path resolver so the app loads
   `<resourcesPath>/Release/wispr-flow-linux-helper`;
   `scripts/patches/mac-gates.sh` gates the macOS "move to Applications" guard to
   `darwin` so it no-ops on Linux. See
   [scripts/README.md](../scripts/README.md) for the exact edits.
4. **Stage native modules** for the Linux Electron 42 ABI. The app ships Windows
   `.node`; the build swaps in pinned, prebuilt linux `better_sqlite3.node` +
   `node_sqlite3.node` fetched and verified by
   `scripts/setup/fetch-native-bin.sh` (with an opt-in local from-source rebuild
   (see below).
5. **Drop `win-ca`/`crypt32`** (Windows cert store; Linux uses the system CA
   bundle); keep the Jabra Linux ELF (already cross-platform).
6. **Stage Linux Electron 42**, repack `app.asar`, and stage the full resources
   tree (migrations, assets, the helper).
7. **Package** as an AppImage via `scripts/packaging/appimage.sh`.

`scripts/verify-patches.sh` static-greps the repacked `app.asar` for the Linux
patch markers, so a half-patched bundle fails the build instead of shipping
broken. I added that gate after getting burned by a silently-incomplete patch.

## Manual / network-dependent steps

Three steps need network + toolchain, so they can't run fully offline:

### Linux Electron download

The build fetches **Electron 42.3.0** for `linux-x64` (or `linux-arm64`) from
the upstream releases. `scripts/setup/fetch-electron-binary.js` drives this, so
you don't pick the runtime by hand.

### The clean-room helper (prebuilt, with a `HELPER_BIN` override)

The helper is consumed like the native modules: a prebuilt release asset pinned
in `helper-version.txt`. When `HELPER_BIN` is unset, staging auto-fetches that
tag from the [helper repo](https://github.com/wispr-flow-linux/helper)'s
releases into `helper-bin/` via `scripts/setup/fetch-helper-bin.sh`. No env
var, no manual step.

To use a local build instead (e.g. while hacking on the helper), point
`HELPER_BIN` at it:

```bash
HELPER_BIN=/path/to/helper/target/release/wispr-flow-linux-helper \
  ./build.sh --exe "$HOME/Downloads/Wispr Flow Setup-v1.6.7.exe"
```

An explicit `HELPER_BIN` is always respected: if it points at a missing or
non-executable file the build warns and does **not** fetch over it, and
packaging then refuses the helper-less tree.

A fetched copy is stamped with its release tag (`helper-bin/.tag`), so when
`helper-version.txt` is bumped the stale cache is refetched automatically on
the next build. Offline, you can also pre-drop a binary at
`helper-bin/wispr-flow-linux-helper`. An executable there without a stamp is
treated as a deliberate local drop and used as-is.

### Native sqlite modules (prebuilt, with an opt-in local rebuild)

Electron 42 ships **V8 14.8 / Node 24.15**, and that combo is where this gets
fiddly. `better-sqlite3-multiple-ciphers` **does not compile** against V8 14.8
unpatched, and a binary's glibc floor is set by where it's built, so the port
treats the two sqlite addons like the clean-room helper: built **once**, on an
old-glibc base, and consumed as pinned, checksummed release assets.

Like the helper, the build + releases live in their **own repo**
([`wispr-flow-linux/native-modules`](https://github.com/wispr-flow-linux/native-modules)),
split out so these CI-consumed artifacts don't inflate the main project's
Release download counts.

- **Producer.** The Build Native Modules workflow in the `native-modules`
  repo rebuilds both addons on `manylinux_2_28` (glibc 2.28 floor) per arch,
  validates each under real Electron (ABI 146 + an encrypted-DB round-trip), and
  publishes them to the tag pinned in `native-modules-version.txt`. The actual
  build is `scripts/rebuild-native-modules.sh` (lockfile-pinned `npm ci`, the V8
  patch on a pristine checkout, isolated electron-gyp headers).
- **Consumer.** The build fetches the matching pair via
  `scripts/setup/fetch-native-bin.sh`, which verifies the SHA-256 **and** the
  provenance stamp (the asset's `patch_sha256` must equal this checkout's patch;
  ABI must be 146) before staging. CI hard-fails if the fetch fails.

For local hacking without a published asset, re-run with
`WISPR_NATIVE_REBUILD=1` and `build-linux.sh` Step 4 builds from source against
your **host** glibc (fine for "does it launch here", not for distributable
packages; `rebuild-native-modules.sh` is vendored here to back this). To drive
it directly:

```bash
ELECTRON_BIN=/path/to/electron \
  scripts/rebuild-native-modules.sh x86_64 native-modules/
```

The patch makes three version-guarded V8-API fixes (External tag, `HolderV2()`,
`SetNativeDataProperty` ambiguity). I wrote up the why in
[learnings/electron42-v8-sqlite.md](learnings/electron42-v8-sqlite.md) if you
want the full story. And don't skip the modules to save time. The app still
launches, but every DB-backed feature breaks.

### The mandatory `electron` → `wispr-flow` rename

**The Electron binary MUST be renamed off `electron`** (to `wispr-flow`). This
one cost me real time, so I want it loud. Electron sets `app.isPackaged=false`
when the launcher is literally named `electron`, so the app resolves the *dev*
migrations path (which doesn't exist), runs 0 migrations, and every DB query
fails with **"no such table"**. Renaming flips `isPackaged=true`, all
92 migrations run, and the errors vanish. The packaging makers do this rename
automatically. The launcher also exports `ELECTRON_FORCE_IS_PACKAGED=true` as
belt-and-braces (see `scripts/launcher-common.sh`). I put the full write-up in
[learnings/ispackaged-rename.md](learnings/ispackaged-rename.md).

## Troubleshooting

Hit a build or runtime problem? Start with
[troubleshooting.md](troubleshooting.md), and run `wispr-flow --doctor` on the
installed package. The doctor surface usually points you at the cause faster
than reading logs by hand.
