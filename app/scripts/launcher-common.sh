#!/usr/bin/env bash
# Common launcher functions for the Wispr Flow AppImage on Omarchy. Sourced by
# the AppImage's AppRun (scripts/packaging/appimage.sh writes it) so logging,
# session checks and the Electron arguments live in one place.
#
# The app runs on native Wayland with the Flow Bar drawn by the omarchy-shell
# plugin over a Unix socket. There is no X11 or XWayland mode: without a
# Wayland session and the plugin's socket the launcher refuses to start and
# says why.
#
# Env var convention: WISPR_*. Supported overrides:
#   WISPR_NATIVE_FLOWBAR=1  start without waiting for the plugin socket (dev)
#   WISPR_DISABLE_GPU=1     disable GPU / software rasterizer (blank-window
#                           workaround on broken drivers)
#
# Design notes:
#   - WM_CLASS is hardcoded "Wispr Flow" (matches the .desktop
#     StartupWMClass written by the AppImage maker).
#   - No --password-store flag. Wispr Flow uses Electron safeStorage and
#     Electron's keyring autodetect works; omitting the flag keeps the
#     launcher desktop-agnostic.

# WM_CLASS / StartupWMClass — must match upstream productName "Wispr Flow".
readonly WM_CLASS='Wispr Flow'

# User config dir (Electron app name "Wispr Flow" -> ~/.config/Wispr Flow).
# Exposed as a function so doctor.sh and cleanup_stale_lock agree on it.
wispr_config_dir() {
	printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/Wispr Flow"
}

# Setup logging directory and file.
# Sets: log_dir, log_file
setup_logging() {
	log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wispr-flow"
	mkdir -p "$log_dir" || return 1
	log_file="$log_dir/launcher.log"
}

# Log a message to the log file.
# Usage: log_message "message"
log_message() {
	echo "$1" >> "$log_file"
}

# Log the session/display environment vars that drive backend and input
# decisions, so bug reports carry enough context without an env-dump
# round trip.
#
# Emits one block:
#     env={
#       KEY=value
#       ...
#     }
#
# Empty or unset values are emitted as `KEY=` so absence is unambiguous
# (vs. silently omitted). Caller must run setup_logging first.
log_session_env() {
	local key
	log_message 'env={'
	for key in \
		XDG_SESSION_TYPE \
		WAYLAND_DISPLAY \
		DISPLAY \
		XDG_CURRENT_DESKTOP \
		WISPR_NATIVE_FLOWBAR \
		WISPR_DISABLE_GPU
	do
		log_message "  $key=${!key:-}"
	done
	log_message '}'
}

# Check if we have a valid display (not running from a TTY).
# Returns: 0 if a display is available, 1 if not.
check_display() {
	[[ -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ]]
}

# Native Flow Bar: the omarchy-shell plugin serves the Flow Bar over a Unix
# socket and Electron runs on native Wayland with its own status window never
# mapped. WISPR_NATIVE_FLOWBAR=1 skips the socket check (development).
# Sets: native_flowbar_socket.
native_flowbar_enabled() {
	native_flowbar_socket="${XDG_RUNTIME_DIR:-/tmp}/wispr-flow/flowbar.sock"
	[[ ${WISPR_NATIVE_FLOWBAR:-} == '1' || -S $native_flowbar_socket ]]
}

# Build the Electron arguments for the AppImage on a Wayland session with the
# native Flow Bar. Returns 1 when the session is not Wayland or the plugin is
# not serving the bar; `launch_error` then holds the reason for the user.
# Sets: electron_args array, launch_error.
# Exports: WISPR_NATIVE_FLOWBAR, WISPR_FLOWBAR_SOCKET, GDK_BACKEND.
build_electron_args() {
	launch_error=''
	# The AppImage runs from a FUSE mount where chrome-sandbox loses its
	# setuid bit, so Electron must be told not to sandbox itself.
	electron_args=('--no-sandbox' "--class=$WM_CLASS")

	# WISPR_DISABLE_GPU=1: opt-in workaround for blank windows / GPU
	# process crashes on broken drivers.
	if [[ ${WISPR_DISABLE_GPU:-} == '1' ]]; then
		log_message 'WISPR_DISABLE_GPU=1 - hardware acceleration disabled'
		electron_args+=('--disable-gpu' '--disable-software-rasterizer')
	fi

	if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
		launch_error='Wispr Flow on Omarchy needs a Wayland session (WAYLAND_DISPLAY is unset).'
		log_message "$launch_error"
		return 1
	fi
	if ! native_flowbar_enabled; then
		launch_error="The Flow Bar plugin is not running (no socket at $native_flowbar_socket). Install it with scripts/omarchy/install-flowbar-plugin.sh --reload, then start Wispr Flow again."
		log_message "$launch_error"
		return 1
	fi

	log_message "Native Flow Bar socket present ($native_flowbar_socket) - native Wayland backend"
	export WISPR_NATIVE_FLOWBAR=1
	export WISPR_FLOWBAR_SOCKET="$native_flowbar_socket"
	electron_args+=('--enable-features=UseOzonePlatform,WaylandWindowDecorations')
	electron_args+=('--ozone-platform=wayland')
	electron_args+=('--enable-wayland-ime')
	electron_args+=('--wayland-text-input-version=3')
	# Override a system-wide GDK_BACKEND=x11 that would otherwise stop GTK
	# from connecting to the compositor (blurry/failed HiDPI).
	export GDK_BACKEND=wayland
	return 0
}

# Set common environment variables.
setup_electron_env() {
	# ELECTRON_FORCE_IS_PACKAGED makes app.isPackaged return true so the
	# app resolves resources via process.resourcesPath. Belt-and-braces:
	# the Electron binary is also renamed to 'wispr-flow' (off 'electron')
	# for the same reason, but the env var guarantees it.
	export ELECTRON_FORCE_IS_PACKAGED=true
}

# Clean up a stale Electron SingletonLock if the owning process is gone.
# requestSingleInstanceLock() silently quits the new instance when the
# lock is held; a stale lock (crash / unclean update) then blocks every
# launch with no user-facing error. The lock is a symlink -> "hostname-PID".
cleanup_stale_lock() {
	local config_dir lock_file
	config_dir="$(wispr_config_dir)"
	lock_file="$config_dir/SingletonLock"

	[[ -L $lock_file ]] || return 0

	local lock_target
	lock_target="$(readlink "$lock_file" 2>/dev/null)" || return 0

	local lock_pid="${lock_target##*-}"

	# Validate that we extracted a numeric PID.
	[[ $lock_pid =~ ^[0-9]+$ ]] || return 0

	if kill -0 "$lock_pid" 2>/dev/null; then
		# Process still running — lock is valid.
		return 0
	fi

	# Chromium treats Lock, Cookie, and Socket as one singleton set. Removing
	# only the lock leaves the stale socket discoverable, and Electron exits with
	# "app is already running" even though the recorded PID is dead. Remove only
	# symlinks (Chromium's normal representation), preserving any unexpected
	# regular user files.
	local singleton
	for singleton in SingletonLock SingletonCookie SingletonSocket; do
		[[ -L $config_dir/$singleton ]] && rm -f "$config_dir/$singleton"
	done
	log_message "Removed stale Chromium singleton set (PID $lock_pid no longer running)"
}

#===============================================================================
# Input-access udev rule installer (--install-udev-rules)
#
# An AppImage has no root post-install hook, so this writes the rule, then
# reloads + triggers udev. Escalates via pkexec (graphical) or sudo.
#===============================================================================

# Canonical rule text.
_wispr_udev_rules_content() {
	cat <<'UDEV'
# Wispr Flow: grant the active-session user the input access the helper needs.
#  - write /dev/uinput        — keystroke injection (PasteText/SimulateKeyPress)
#  - read  /dev/input/event*  — global key monitor for push-to-talk and the
#                               in-app shortcut recorder
# TAG+="uaccess" scopes the grant to the active logind session; the input group
# + 0660 is the cross-distro fallback (then `usermod -aG input $USER` + re-login).
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess", GROUP="input", MODE="0660"
UDEV
}

# Install the rule into /usr/lib/udev/rules.d and reload udev. Returns non-zero
# on failure. Needs root: runs directly if already root, else pkexec, else sudo.
install_udev_rules() {
	local rule_dst='/usr/lib/udev/rules.d/70-wispr-flow-uinput.rules'
	local tmp
	tmp="$(mktemp)" || {
		echo 'Error: mktemp failed' >&2
		return 1
	}
	_wispr_udev_rules_content > "$tmp"

	# The privileged half as one script, so a single escalation does everything.
	local script
	printf -v script '%s\n' \
		'set -e' \
		"install -D -m 0644 '$tmp' '$rule_dst'" \
		'if command -v udevadm >/dev/null 2>&1; then' \
		'	udevadm control --reload-rules || true' \
		'	udevadm trigger --subsystem-match=misc --sysname-match=uinput || true' \
		'	udevadm trigger --subsystem-match=input || true' \
		'fi'

	echo "Installing udev rule -> $rule_dst"
	local rc
	if [[ $EUID -eq 0 ]]; then
		bash -c "$script"
		rc=$?
	elif command -v pkexec >/dev/null 2>&1 \
		&& [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
		pkexec bash -c "$script"
		rc=$?
	elif command -v sudo >/dev/null 2>&1; then
		sudo bash -c "$script"
		rc=$?
	else
		echo 'Error: need root to install the rule.' >&2
		echo 'Install pkexec or sudo, or re-run this command as root.' >&2
		rm -f "$tmp"
		return 1
	fi
	rm -f "$tmp"

	if [[ $rc -ne 0 ]]; then
		echo "Error: udev rule install failed (exit $rc)." >&2
		return "$rc"
	fi
	echo 'Done. The rule grants the active-session user input access for'
	echo 'keystroke injection (/dev/uinput) and push-to-talk (/dev/input read).'
	echo 'Already-open sessions may need a re-login (or device replug) to pick'
	echo 'up the new ACL. Verify with: wispr-flow --doctor'
	return 0
}

#===============================================================================
# Doctor Diagnostics
#
# run_doctor and its helpers live in doctor.sh next to this file. Sourced
# here so any consumer of launcher-common.sh gets the run_doctor entry
# point. The AppImage installs doctor.sh alongside this file.
#===============================================================================
# shellcheck source=scripts/doctor.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/doctor.sh"
