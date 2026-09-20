# shellcheck shell=bash
# shellcheck disable=SC2034  # globals set here are consumed by build.sh (the sourcing script)
# shellcheck disable=SC2154  # project_root is assigned by build.sh before parse_arguments runs
#===============================================================================
# detect-host.sh -- host detection + CLI flag parsing for the Wispr Flow build.
#
# Sourced by: build.sh
# Requires:   scripts/_common.sh (say/warn/die) already sourced.
#
# Sets these globals (declared in build.sh):
#   arch            uname-style arch used by the AppImage: x86_64 | aarch64
#   electron_arch   Electron dist naming:                 x64    | arm64
#   clean_action, local_exe_path, release_tag, test_flags_mode, work_dir
#===============================================================================

# --- architecture -------------------------------------------------------------
detect_architecture() {
	local raw_arch
	raw_arch=$(uname -m) || die 'Failed to detect machine architecture'
	echo "Detected machine architecture: $raw_arch"

	case "$raw_arch" in
		x86_64|amd64)
			arch='x86_64'
			electron_arch='x64'
			;;
		aarch64|arm64)
			arch='aarch64'
			electron_arch='arm64'
			;;
		*)
			die "Unsupported architecture: $raw_arch (supported: x86_64/amd64, aarch64/arm64)"
			;;
	esac
	echo "Arch: $arch (electron=$electron_arch)"
}

# Map a requested --arch value (amd64|arm64|x86_64|aarch64) onto the arch
# globals. Used by parse_arguments when --arch overrides the detected host
# arch (e.g. cross-target test runs).
set_arch_from_request() {
	local req="$1"
	case "${req,,}" in
		amd64|x86_64|x64)
			arch='x86_64'; electron_arch='x64' ;;
		arm64|aarch64)
			arch='aarch64'; electron_arch='arm64' ;;
		*)
			die "Invalid --arch '$req' (must be amd64|arm64)" ;;
	esac
}

# --- system requirements ------------------------------------------------------
check_system_requirements() {
	# Allow root only in CI/container; otherwise require a normal user (we sudo
	# explicitly when a privileged action is actually needed).
	if (( EUID == 0 )); then
		if [[ -n ${CI:-} || -n ${GITHUB_ACTIONS:-} || -f /.dockerenv ]]; then
			echo 'Running as root in CI/container environment (allowed)'
		else
			die 'Do not run this script as root/sudo. Run as a normal user; it will sudo only when needed.'
		fi
	fi

	original_user=$(whoami)
	original_home=$(getent passwd "$original_user" | cut -d: -f6)
	[[ -n $original_home ]] || die "Could not determine home directory for user $original_user"
	echo "Running as user: $original_user (Home: $original_home)"
}

# --- argument parsing ---------------------------------------------------------
parse_arguments() {
	# Defaults. work_dir matches the existing build-linux.sh layout.
	work_dir="$project_root/build-linux"

	while (( $# > 0 )); do
		case "$1" in
			--arch|-e|--exe|-c|--clean|-r|--release-tag)
				if [[ -z ${2:-} || $2 == -* ]]; then
					die "Argument for $1 is missing"
				fi
				case "$1" in
					--arch)           set_arch_from_request "$2" ;;
					-e|--exe)         local_exe_path="$2" ;;
					-c|--clean)       clean_action="${2,,}" ;;
					-r|--release-tag) release_tag="$2" ;;
				esac
				shift 2
				;;
			--test-flags)
				test_flags_mode=true
				shift
				;;
			-h|--help)
				print_usage
				exit 0
				;;
			*)
				warn "Unknown option: $1"
				echo 'Use -h or --help for usage information.' >&2
				exit 1
				;;
		esac
	done

	# --- validation ---
	case "$clean_action" in
		yes|no) ;;
		*) die "Invalid --clean '$clean_action' (must be yes|no)" ;;
	esac

	if [[ -n $local_exe_path && ! -f $local_exe_path ]]; then
		die "--exe path does not exist: $local_exe_path"
	fi
}

print_usage() {
	cat <<EOF
Usage: ./build.sh [options]

Builds the unofficial Wispr Flow AppImage from the Windows installer.

Options:
      --arch <arch>      Target architecture: amd64 | arm64
                         (default: detected host arch -> '$arch')
  -e, --exe <path>       Path to a Wispr Flow installer .exe you obtained
                         yourself (optional; default: fetch the latest installer
                         from Wispr's official endpoint)
  -c, --clean <yes|no>   Remove intermediate build files when done (default: no)
  -r, --release-tag <t>  Optional release tag to embed in the package version
      --test-flags       Parse + print resolved flags, then exit WITHOUT building
  -h, --help             Show this help and exit

Notes:
  * The build wraps scripts/build-linux.sh (staging) and
    scripts/packaging/appimage.sh (packaging); it never rewrites them.
  * Install the result with packaging/arch/PKGBUILD (see the README).
  * Native sqlite addons are fetched as a pinned prebuilt from the
    wispr-flow-linux/native-modules repo (pinned in native-modules-version.txt).
    Set WISPR_NATIVE_REBUILD=1 to build a local, non-portable copy from source
    instead (dev only; needs node/npm + a C/C++ toolchain).
EOF
}
