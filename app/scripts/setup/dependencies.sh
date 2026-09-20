# shellcheck shell=bash
#===============================================================================
# dependencies.sh -- check the commands the build needs and name the Arch
# packages that provide them. Nothing is installed automatically.
#
# Sourced by: build.sh
# Requires:   scripts/_common.sh (check_command/warn/die) already sourced.
#
#   7z         (7zip)         -- extract the Squirrel installer .exe / .nupkg
#   curl                      -- download installer + Electron dist
#   wrestool, icotool (icoutils) -- pull the icon out of the Windows exe
#   convert    (imagemagick)  -- icon conversion/resizing
#   rsync                     -- stage resource trees
#   node, npx  (nodejs, npm)  -- @electron/asar pack/unpack + helpers
#   python3                   -- run the bundle patch suite (scripts/patches/*)
#   appimagetool              -- packaging/appimage.sh (not in the repos; see README)
#
# The native sqlite addons are fetched as pinned prebuilt assets
# (scripts/setup/fetch-native-bin.sh), so no C/C++ toolchain is needed. The
# helper is built separately with cargo (helper/) and picked up from
# helper/target/release by build-linux.sh.
#===============================================================================

check_dependencies() {
	echo 'Checking build dependencies...'

	declare -A arch_pkgs=(
		[7z]='7zip' [curl]='curl' [wrestool]='icoutils' [icotool]='icoutils'
		[convert]='imagemagick' [rsync]='rsync' [node]='nodejs' [npx]='npm'
		[python3]='python'
	)

	local cmd missing='' pkgs=''
	for cmd in 7z curl wrestool icotool convert rsync node npx python3; do
		check_command "$cmd" && continue
		missing="$missing $cmd"
		case " $pkgs " in
			*" ${arch_pkgs[$cmd]} "*) ;;
			*) pkgs="$pkgs ${arch_pkgs[$cmd]}" ;;
		esac
	done

	if [[ -n $missing ]]; then
		warn "Missing build tools:$missing"
		die "Install them first:  sudo pacman -S --needed$pkgs"
	fi
	if ! check_command appimagetool; then
		warn 'appimagetool not found on PATH; scripts/packaging/appimage.sh needs it'
		warn '  (download it to ~/.local/bin as described in the README).'
	fi
	echo 'All required build dependencies are present.'
}
