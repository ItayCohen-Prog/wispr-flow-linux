#!/usr/bin/env bash
#===============================================================================
# install-flowbar-plugin.sh -- link the native Flow Bar plugin into the user's
# omarchy-shell plugin directory and enable it.
#
# Usage: install-flowbar-plugin.sh [--uninstall]
#===============================================================================
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_dir/omarchy/plugins/wispr.flowbar"
dst="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/wispr.flowbar"

if ! command -v omarchy-shell >/dev/null; then
	echo 'ERROR: omarchy-shell not found; this plugin needs Omarchy.' >&2
	exit 1
fi

if [[ ${1:-} == '--uninstall' ]]; then
	omarchy-shell shell disablePlugin wispr.flowbar >/dev/null 2>&1
	rm -f "$dst"
	omarchy-shell shell rescanPlugins >/dev/null 2>&1
	echo "Removed $dst"
	exit 0
fi

if [[ ! -f "$src/manifest.json" ]]; then
	echo "ERROR: plugin source not found at $src" >&2
	exit 1
fi

mkdir -p "$(dirname "$dst")" || exit 1
if [[ -e $dst && ! -L $dst ]]; then
	echo "ERROR: $dst exists and is not a symlink; remove it first." >&2
	exit 1
fi
ln -sfn "$src" "$dst" || exit 1
echo "Linked $dst -> $src"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 \
	|| echo 'WARNING: omarchy-shell rescanPlugins failed (shell not running?)' >&2
# The rescan is asynchronous; retry the enable until the registry knows the id.
for _ in 1 2 3 4 5 6 7 8 9 10; do
	if omarchy-shell shell listPlugins 2>/dev/null \
		| grep -q '"id":"wispr.flowbar"[^}]*"enabled":true'; then
		break
	fi
	omarchy-shell shell enablePlugin wispr.flowbar '{}' >/dev/null 2>&1
	sleep 0.5
done

sock="${XDG_RUNTIME_DIR:-/tmp}/wispr-flow/flowbar.sock"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[[ -S $sock ]] && break
	sleep 0.5
done
if [[ -S $sock ]]; then
	echo "OK: plugin enabled, socket at $sock"
	echo 'Restart Wispr Flow; the launcher now picks native Wayland.'
else
	echo "WARNING: socket not present at $sock yet; check omarchy-shell log." >&2
fi
