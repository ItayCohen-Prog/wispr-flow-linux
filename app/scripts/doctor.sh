# shellcheck shell=bash
#===============================================================================
# Doctor Diagnostics for Wispr Flow
#
# Sourced by: scripts/launcher-common.sh (in turn sourced by the per-package
# AppImage's AppRun launcher).
#
# Provides: run_doctor (the `wispr-flow --doctor` entry point) plus its
# internal helpers. Self-contained — no dependency on launcher-common.sh
# state, though it reuses wispr_config_dir() when available.
#
# Scoped to Wispr Flow's load-bearing runtime requirements: /dev/uinput
# write access (keystroke injection), input-group fallback, wl-clipboard /
# AT-SPI accessibility, the Flow Bar plugin socket,
# (relogin caveat), the helper-binary launch probe, and recent crashes.
#
# To add a check: define `_check_<name>`, call it from run_doctor, and use
# _pass / _fail / _warn / _info. _fail increments _doctor_failures (local to
# run_doctor) which becomes the exit status.
#===============================================================================


# Color helpers (disabled when stdout is not a terminal).
_doctor_colors() {
	if [[ -t 1 ]]; then
		_green='\033[0;32m'
		_red='\033[0;31m'
		_yellow='\033[0;33m'
		_bold='\033[1m'
		_reset='\033[0m'
	else
		_green='' _red='' _yellow='' _bold='' _reset=''
	fi
}

_pass() { echo -e "${_green}[PASS]${_reset} $*"; }
_fail() {
	echo -e "${_red}[FAIL]${_reset} $*"
	_doctor_failures=$((_doctor_failures + 1))
}
_warn() { echo -e "${_yellow}[WARN]${_reset} $*"; }
_info() { echo -e "       $*"; }

# Resolve the user config dir even when this file is sourced standalone
# (i.e. without launcher-common.sh defining wispr_config_dir).
_doctor_config_dir() {
	if declare -F wispr_config_dir &>/dev/null; then
		wispr_config_dir
	else
		printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/Wispr Flow"
	fi
}

#------------------------------------------------------------------------------
# Display / session backend.
#------------------------------------------------------------------------------
_doctor_check_display() {
	if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
		_pass "Display server: Wayland (WAYLAND_DISPLAY=$WAYLAND_DISPLAY)"
		_info 'Mode: native Wayland; the Flow Bar is drawn by the omarchy-shell plugin'
	elif [[ -n ${DISPLAY:-} ]]; then
		_fail "Display server: X11 only (DISPLAY=$DISPLAY); this build needs a Wayland session"
		_info 'Fix: log in to Hyprland (Omarchy) and run Wispr Flow there'
		return
	else
		_fail 'No display server detected' \
			'(DISPLAY and WAYLAND_DISPLAY are unset)'
		_info 'Fix: run from within a Wayland session, not a TTY'
		return
	fi

	# Compositor from XDG_CURRENT_DESKTOP (may be colon-separated).
	local desktop="${XDG_CURRENT_DESKTOP:-unknown}"
	case "${desktop,,}" in
		*hyprland*) _info "Desktop: $desktop" ;;
		*) _warn "Desktop: $desktop (only Hyprland on Omarchy is tested)" ;;
	esac
}

#------------------------------------------------------------------------------
# Native Flow Bar — the omarchy-shell plugin must be serving its socket, or the
# launcher refuses to start.
#------------------------------------------------------------------------------
_doctor_check_flowbar_socket() {
	local sock="${XDG_RUNTIME_DIR:-/tmp}/wispr-flow/flowbar.sock"
	if [[ -S $sock ]]; then
		_pass "Flow Bar plugin: socket present ($sock)"
	else
		_fail "Flow Bar plugin: no socket at $sock"
		_info 'The omarchy-shell plugin draws the Flow Bar; without it Wispr Flow will not start.'
		_info 'Fix: app/scripts/omarchy/install-flowbar-plugin.sh --reload  (from the repo clone)'
	fi
}

#------------------------------------------------------------------------------
# /dev/uinput — the load-bearing check for keystroke injection.
#------------------------------------------------------------------------------
_doctor_check_uinput() {
	local node='/dev/uinput'
	if [[ ! -e $node ]]; then
		_fail '/dev/uinput: missing (uinput kernel module not loaded)'
		_info 'Fix: sudo modprobe uinput  (and ensure it loads at boot)'
		return
	fi
	if [[ -w $node ]]; then
		_pass '/dev/uinput: writable (keystroke injection available)'
		return
	fi
	_fail '/dev/uinput: exists but NOT writable by current user'
	_info 'Keystroke injection (paste / SimulateKeyPress) will fail.'
	_info 'Fix (preferred, persistent): install the udev rule'
	_info '  KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput",'
	_info '  TAG+="uaccess", GROUP="input", MODE="0660"'
	_info '  then: sudo udevadm control --reload-rules && sudo udevadm trigger'
	# SC2016: literal $USER is intentional — these are copy-paste remedies
	# the user runs in their own shell, not expanded here.
	# shellcheck disable=SC2016
	_info 'Fix (group fallback): sudo usermod -aG input "$USER"  (then re-login)'
	# shellcheck disable=SC2016
	_info 'Fix (this session only): sudo setfacl -m u:$USER:rw /dev/uinput'
}

#------------------------------------------------------------------------------
# input group — fallback grant path when the uaccess ACL is absent.
#------------------------------------------------------------------------------
_doctor_check_input_group() {
	if ! getent group input &>/dev/null; then
		_info 'input group: not present on this system (uaccess ACL path only)'
		return
	fi
	if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx 'input'; then
		_pass 'input group: current user is a member'
	else
		# Not necessarily a failure: a uaccess ACL may already grant
		# /dev/uinput access. Only warn so the uinput check stays the
		# authoritative signal.
		_warn 'input group: current user is NOT a member'
		_info 'Harmless if /dev/uinput is already writable above.'
		# shellcheck disable=SC2016  # literal $USER: copy-paste remedy
		_info 'Otherwise: sudo usermod -aG input "$USER"  (then re-login)'
	fi
}

#------------------------------------------------------------------------------
# /dev/input read — load-bearing for push-to-talk and the shortcut recorder.
# The helper monitors global keys by reading /dev/input/event* (evdev); without
# read access no KeypressEvent reaches the app, so no hotkey ever fires and the
# in-app shortcut recorder captures nothing.
#------------------------------------------------------------------------------
# shellcheck disable=SC2120  # $1 (dir) is an optional test seam; prod uses the
# default /dev/input, tests/doctor.bats drives it with fake event nodes.
_doctor_check_input_read() {
	# dir override (default /dev/input) keeps this testable with fake nodes.
	local dir="${1:-/dev/input}" dev readable=0 total=0
	if [[ ! -d $dir ]]; then
		_fail '/dev/input: missing (no evdev input layer)'
		return
	fi
	for dev in "$dir"/event*; do
		[[ -e $dev ]] || continue
		total=$((total + 1))
		[[ -r $dev ]] && readable=$((readable + 1))
	done
	if ((total == 0)); then
		_warn '/dev/input: no event devices found'
		return
	fi
	if ((readable > 0)); then
		_pass "/dev/input: ${readable}/${total} event device(s) readable" \
			'(push-to-talk available)'
		return
	fi
	_fail "/dev/input: none of ${total} event device(s) readable"
	_info 'Push-to-talk and the in-app shortcut recorder will not work.'
	_info 'Fix (easiest): wispr-flow --install-udev-rules  (installs the rule via pkexec/sudo)'
	# shellcheck disable=SC2016  # literal $USER: copy-paste remedy
	_info 'Fix (group, grants both input read + uinput write): sudo usermod -aG input "$USER"  (then re-login)'
}

#------------------------------------------------------------------------------
# Clipboard tools — hard requirement on Wayland (paste/selection).
#------------------------------------------------------------------------------
_doctor_check_clipboard() {
	if command -v wl-copy &>/dev/null && command -v wl-paste &>/dev/null; then
		_pass 'Clipboard: wl-copy and wl-paste present'
	else
		_fail 'Clipboard: wl-clipboard missing (wl-copy / wl-paste)'
		_info 'Paste and selection capture require it.'
		_info 'Fix: sudo pacman -S wl-clipboard'
	fi
}

#------------------------------------------------------------------------------
# AT-SPI accessibility — best-effort. Off by default; the helper enables it.
#------------------------------------------------------------------------------
_doctor_check_atspi() {
	# Preferred signal: the gsettings toggle the helper flips
	# (set_session_accessibility). Absent gsettings -> fall back to probing
	# the a11y bus address.
	local enabled=''
	if command -v gsettings &>/dev/null; then
		enabled=$(gsettings get org.gnome.desktop.interface toolkit-accessibility \
			2>/dev/null) || enabled=''
	fi

	if [[ $enabled == 'true' ]]; then
		_pass 'AT-SPI: accessibility enabled (toolkit-accessibility=true)'
		return
	fi

	# Probe whether an a11y bus is reachable at all (per-app dictation /
	# selection reads still work once the helper enables it at runtime).
	local a11y_reachable=false
	if command -v dbus-send &>/dev/null; then
		if dbus-send --session --print-reply --reply-timeout=1000 \
			--dest=org.a11y.Bus /org/a11y/bus \
			org.a11y.Bus.GetAddress &>/dev/null
		then
			a11y_reachable=true
		fi
	fi

	if [[ $enabled == 'false' ]]; then
		_warn 'AT-SPI: accessibility disabled (toolkit-accessibility=false)'
		_info 'Off by default; the helper enables it at runtime (best-effort).'
		_info 'Selection reads (GetSelectedText) may be empty until then.'
	elif [[ $a11y_reachable == true ]]; then
		_pass 'AT-SPI: a11y bus reachable (org.a11y.Bus)'
	else
		_warn 'AT-SPI: accessibility state unknown (a11y bus not reachable)'
		_info 'The helper enables accessibility at runtime; this is usually fine.'
	fi
}

#------------------------------------------------------------------------------
# Helper binary — present, executable, and actually launches. Stat checks
# alone green-lit a helper that aborted at exec with `GLIBC_2.39 not found`
# (wispr-flow-linux/helper#1, #16), so probe by running `--version` with
# stdin at EOF:
#   * helper >= v0.1.2 prints its version and exits 0
#   * older helpers ignore argv, hit stdin EOF, and exit 0 silently
#   * a binary that cannot start exits non-zero with the loader's
#     message on stderr — surfaced below
# fd 3 (the helper's IPC return channel) is redirected to /dev/null so a
# probed helper can never write frames into a descriptor the launcher
# happens to have open.
#------------------------------------------------------------------------------
_doctor_check_helper() {
	local helper_path="${1:-}"
	if [[ -z $helper_path ]]; then
		_warn 'Helper binary: path not provided to doctor'
		return
	fi
	if [[ ! -e $helper_path ]]; then
		_fail "Helper binary: not found at $helper_path"
		_info 'Text injection / active-app detection will not work.'
		_info 'Fix: reinstall the wispr-flow package'
		return
	fi
	if [[ ! -x $helper_path ]]; then
		local perms
		perms=$(stat -c '%a' "$helper_path" 2>/dev/null || echo '?')
		_fail "Helper binary: not executable (perms=$perms) at $helper_path"
		_info "Fix: chmod +x '$helper_path'"
		return
	fi

	local timeout_s="${WISPR_DOCTOR_HELPER_TIMEOUT:-5}"
	local err_file probe_out status=0
	err_file=$(mktemp "${TMPDIR:-/tmp}/wispr-doctor-helper.XXXXXX")
	probe_out=$(timeout "$timeout_s" "$helper_path" --version \
		</dev/null 2>"$err_file" 3>/dev/null) || status=$?

	if [[ $status -eq 0 ]]; then
		if [[ $probe_out == wispr-flow-linux-helper* ]]; then
			_pass "Helper binary: launches OK ($probe_out)"
		else
			_pass "Helper binary: launches OK ($helper_path)"
			_info 'Helper predates --version (< v0.1.2); no version reported.'
		fi
		rm -f "$err_file"
		return
	fi

	if [[ $status -eq 124 ]]; then
		_fail "Helper binary: still running after ${timeout_s}s probe" \
			"at $helper_path"
		_info 'The helper did not exit on stdin EOF; it may be wedged.'
	else
		_fail "Helper binary: cannot launch (exit $status) at $helper_path"
		_info 'Text injection / push-to-talk will not work.'
	fi
	# Surface the launch-failure cause (e.g. `GLIBC_2.39 not found`).
	local line
	while IFS= read -r line; do
		_info "stderr: $line"
	done < <(tail -n 3 "$err_file")
	rm -f "$err_file"
}

#------------------------------------------------------------------------------
# Recent crashes — scan launcher.log tail for crash / FATAL markers.
#------------------------------------------------------------------------------
_doctor_check_recent_crashes() {
	local log_path
	log_path="${XDG_CACHE_HOME:-$HOME/.cache}/wispr-flow/launcher.log"
	[[ -f $log_path ]] || return 0

	# Scan the tail only; the log is append-only and can grow large.
	local hits
	hits=$(tail -n 500 "$log_path" 2>/dev/null \
		| grep -ciE 'FATAL|segfault|SIGSEGV|SIGABRT|core dumped|crashed|GPU process' ) \
		|| hits=0
	[[ $hits =~ ^[0-9]+$ ]] || hits=0

	if ((hits == 0)); then
		_pass 'Recent crashes: none in launcher.log tail'
	else
		_warn "Recent crashes: $hits crash/FATAL marker(s) in launcher.log tail"
		_info "Inspect: tail -n 500 '$log_path' | grep -iE 'FATAL|crash|GPU'"
		_info 'If GPU-related, try WISPR_DISABLE_GPU=1 in the environment.'
	fi
}

#------------------------------------------------------------------------------
# SingletonLock — surface a stale single-instance lock (blocks launches).
#------------------------------------------------------------------------------
_doctor_check_singleton_lock() {
	local config_dir lock_file
	config_dir="$(_doctor_config_dir)"
	lock_file="$config_dir/SingletonLock"
	[[ -L $lock_file ]] || { _pass 'SingletonLock: no lock file (OK)'; return; }

	local lock_target lock_pid
	lock_target="$(readlink "$lock_file" 2>/dev/null)" || true
	lock_pid="${lock_target##*-}"
	if [[ $lock_pid =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
		_pass "SingletonLock: held by running process (PID $lock_pid)"
	else
		_warn "SingletonLock: stale lock (PID ${lock_pid:-?} not running)"
		_info "Fix: rm '$lock_file'  (the launcher also clears this on start)"
	fi
}

#------------------------------------------------------------------------------
# Electron runtime — the renamed Electron binary the launcher exec's must exist
# and be executable. Version is read from the sibling 'version' file rather than
# launching Electron (which can hang).
#------------------------------------------------------------------------------
_doctor_electron_version() {
	local version_file
	version_file="$(dirname "$1")/version"
	[[ -r $version_file ]] && printf '%s' "$(< "$version_file")"
}

_doctor_check_electron() {
	local electron_path="${1:-}"
	if [[ -z $electron_path ]]; then
		_warn 'Electron runtime: path not provided to doctor'
		return
	fi
	if [[ ! -x $electron_path ]]; then
		_fail "Electron runtime: not found / not executable at $electron_path"
		_info 'The launcher cannot start the app.'
		_info 'Fix: reinstall the wispr-flow package'
		return
	fi
	local ver
	ver=$(_doctor_electron_version "$electron_path")
	if [[ $ver =~ ^v?[0-9]+\.[0-9]+ ]]; then
		_pass "Electron runtime: v${ver#v} ($electron_path)"
	else
		_pass "Electron runtime: present and executable ($electron_path)"
	fi
}

#------------------------------------------------------------------------------
# Desktop entry + free disk on the config partition — cheap install-integrity
# checks. Out-of-disk is a known Chromium failure mode (blank window / profile
# corruption) that is otherwise invisible.
#------------------------------------------------------------------------------
_doctor_check_desktop_entry() {
	# The Arch package (packaging/arch/PKGBUILD) installs it under its pkgname.
	local desktop_file
	for desktop_file in \
		/usr/share/applications/wispr-flow-appimage.desktop \
		/usr/share/applications/wispr-flow.desktop
	do
		if [[ -f $desktop_file ]]; then
			_pass "Desktop entry: $desktop_file"
			return
		fi
	done
	_warn 'Desktop entry: not found (expected when running the bare AppImage)'
}

_doctor_check_disk_space() {
	local config_dir avail
	config_dir="$(_doctor_config_dir)"
	avail=$(df -BM --output=avail "$config_dir" 2>/dev/null \
		| tail -1 | tr -d ' M') || true
	[[ $avail =~ ^[0-9]+$ ]] || return 0
	if ((avail < 100)); then
		_fail "Disk space: ${avail}MB free on the config partition"
		_info 'Chromium will fail to write its profile. Fix: free up disk space.'
	elif ((avail < 500)); then
		_warn "Disk space: ${avail}MB free on the config partition (low)"
	else
		_pass "Disk space: ${avail}MB free on the config partition"
	fi
}

#===============================================================================
# Entry point.
# Arguments: $1 = path to the Linux helper binary (helper check).
#            $2 = path to the Electron runtime binary (runtime / sandbox checks
#                 derive the install dir from it). Both optional but recommended.
#===============================================================================
run_doctor() {
	local helper_path="${1:-}"
	local electron_path="${2:-}"
	local _doctor_failures=0
	_doctor_colors

	local arch
	arch=$(uname -m 2>/dev/null || echo 'unknown')
	local session="${XDG_SESSION_TYPE:-unknown}"
	local desktop="${XDG_CURRENT_DESKTOP:-unknown}"

	echo -e "${_bold}Wispr Flow Diagnostics${_reset}"
	echo '=========================='
	echo "Session: $session   Desktop: $desktop   Arch: $arch"
	if [[ -n $helper_path && -x $helper_path ]]; then
		echo "Helper:  $helper_path"
	fi
	echo

	echo -e "${_bold}Display / Session${_reset}"
	_doctor_check_display
	echo

	echo -e "${_bold}Native Flow Bar${_reset}"
	_doctor_check_flowbar_socket
	echo

	echo -e "${_bold}Text Injection (uinput)${_reset}"
	_doctor_check_uinput
	_doctor_check_input_group
	echo

	echo -e "${_bold}Push-to-Talk (input monitor)${_reset}"
	_doctor_check_input_read
	echo

	echo -e "${_bold}Clipboard${_reset}"
	_doctor_check_clipboard
	echo

	echo -e "${_bold}Accessibility (AT-SPI)${_reset}"
	_doctor_check_atspi
	echo

	echo -e "${_bold}Helper & Runtime${_reset}"
	_doctor_check_helper "$helper_path"
	_doctor_check_electron "$electron_path"
	_doctor_check_desktop_entry
	_doctor_check_disk_space
	_doctor_check_singleton_lock
	_doctor_check_recent_crashes
	echo

	if ((_doctor_failures == 0)); then
		echo -e "${_green}${_bold}All checks passed.${_reset}"
	else
		echo -e "${_red}${_bold}${_doctor_failures} check(s) failed.${_reset}"
		echo 'See above for fixes.'
	fi

	return "$_doctor_failures"
}
