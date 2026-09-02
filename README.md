# Wispr Flow on Omarchy

My working setup of [Wispr Flow](https://wisprflow.ai) voice dictation on
Linux. It is a fork of the community port
[wispr-flow-linux](https://github.com/wispr-flow-linux/wispr-flow-linux) and its
Rust [helper](https://github.com/wispr-flow-linux/helper), kept together in one
repo so a single clone gives you everything I run.

> **Only tested on Omarchy** (Arch Linux, Hyprland, omarchy-shell). Nothing here
> has been tried on any other distro or desktop. Other distros should follow the
> upstream docs in `app/docs/` instead, and the Flow Bar plugin below will not
> apply to them.

## What is different from upstream

- **Native Flow Bar on Omarchy.** An omarchy-shell (Quickshell) plugin draws the
  Flow Bar as a layer-shell surface, so the app runs on native Wayland and the
  Hub is a normal managed window. The design notes are in
  `app/docs/decisions.md` (D-010).
- **Helper fix for a stuck Ctrl key.** The upstream helper could re-press a
  modifier you were physically holding on its virtual keyboard, which left Ctrl
  stuck system-wide until the helper was killed. The helper here waits for held
  modifiers to come up and never touches keys outside the chord. It also uses a
  Shift+Insert paste chord.
- **Helper is built from source, not downloaded.** Upstream pins a prebuilt
  helper release. The app build script here uses `helper/target/release` when it
  exists, so the fixed helper ships in the package without any extra setup.

## Layout

```
app/       the Electron repackaging: build scripts, patches, docs, Omarchy plugin
helper/    the clean-room Rust helper (evdev capture, uinput injection)
packaging/arch/PKGBUILD   installs a built AppImage as an Arch package
```

Both folders keep their full upstream history (imported with `git subtree`).

## Setup on Omarchy

### 1. Build dependencies

```bash
sudo pacman -S --needed p7zip icoutils imagemagick rsync nodejs npm python3 curl rustup
rustup default stable
yay -S appimagetool-bin    # or drop appimagetool-x86_64.AppImage in app/build-linux/appimage/
```

### 2. Build the helper

```bash
cd helper
cargo build --release
cargo test
```

The binary lands in `helper/target/release/wispr-flow-linux-helper`. The app
build picks it up from there automatically.

### 3. Build the app

```bash
cd ../app
./build.sh --build appimage
```

This downloads the official Wispr Flow Windows installer, the Linux Electron
runtime, rebuilds the native sqlite module, applies the patches under
`app/scripts/patches/`, and writes an AppImage into `app/build-linux/appimage/`.
The repo never bundles the proprietary app.

### 4. Install it as a package

```bash
cp packaging/arch/PKGBUILD app/build-linux/appimage/
cd app/build-linux/appimage
# edit PKGBUILD: set _appimage to the file you just built and bump pkgver
updpkgsums
makepkg -si
```

That puts the app under `/opt/wispr-flow-appimage` with a `wispr-flow`
launcher and desktop entry. Once, after the first install, grant input access:

```bash
./wispr-flow-*-x86_64.AppImage --install-udev-rules
```

Then log out and back in so the `/dev/uinput` and `/dev/input` permissions
apply.

### 5. Enable the native Flow Bar

```bash
cd ../../..   # back to app/
scripts/omarchy/install-flowbar-plugin.sh
omarchy restart shell
```

The plugin directory is a symlink into this repo, so keep the clone where it is.
After editing plugin code run `omarchy restart shell` again.

### 6. Check

```bash
wispr-flow --doctor
wispr-flow
```

Every check should pass. The launcher switches to native Wayland on its own
when the plugin's socket exists. Push-to-talk is Ctrl+Space by default.

## Updating

```bash
cd helper && cargo build --release && cd ..
cd app && ./build.sh --build appimage
```

then repeat step 4. The previous package stays in `app/build-linux/` as a
rollback.

## Pulling upstream changes

```bash
git subtree pull --prefix=app    https://github.com/wispr-flow-linux/wispr-flow-linux.git main
git subtree pull --prefix=helper https://github.com/wispr-flow-linux/helper.git main
```

## License

Build scripts and the helper are public domain under the Unlicense, as
upstream. Wispr Flow itself is proprietary and subject to its own terms.
