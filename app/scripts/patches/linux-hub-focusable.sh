#!/usr/bin/env bash
#===============================================================================
# linux-hub-focusable.sh -- stop the Flow Hub from being created as an X11
# override-redirect (unmanaged) window on Linux, in the Wispr Flow main bundle
# (.webpack/main/index.js).
#
# WHY THIS PATCH EXISTS
# ---------------------
# Upstream creates the Hub BrowserWindow with `focusable:!1` on EVERY platform.
# On macOS that pairs with the "accessory" activation policy so opening the Hub
# never steals focus from the app being dictated into. Electron implements
# `focusable:false` as `widget_delegate()->SetCanActivate(false)`, and
# Chromium's X11 backend (ui/ozone/platform/x11/x11_window.cc) turns a
# non-activatable top-level into an override-redirect window:
#
#   if (!activatable_ || override_redirect) req.override_redirect = true;
#
# An override-redirect window bypasses the window manager entirely. That is
# issue #36 verbatim (Ubuntu 24.04 GNOME X11: the Hub cannot be moved,
# minimized, maximized or Alt-Tabbed to; xwininfo says "Override Redirect
# State: yes"), and the same on Hyprland/XWayland (always floating, no
# border/shadow, never tiled, activate requests ignored). The `resizable`,
# `movable`, `maximizable` flags in the very same config object are all true;
# `focusable:!1` silently overrides them on X11.
#
# THE PATCH (surgical, one property)
# ----------------------------------
# At the Hub window-config object only, keep the upstream value on macOS and
# Windows (false) and make the window focusable on Linux (true):
#
#   ...,"hub","preload.js"),devTools:...},focusable:!1};
#     becomes
#   ...,"hub","preload.js"),devTools:...},
#     focusable:/*WISPR_LINUX_HUB_FOCUSABLE*/"linux"===process.platform};
#
# Anchor: the developer path literal `"hub","preload.js")` (unique in the
# bundle) followed -- within the same object literal, no `;`/`{`/`}` crossed --
# by `},focusable:!1}`. That pins the Hub config and nothing else (the overlay /
# status / context-menu windows also pass focusable:!1 but sit nowhere near the
# hub preload path). The count is asserted at exactly 1.
#
# Nothing else changes: the mac-only focus-suppression helpers
# (`withHubFocusSuppressed`, gated on the darwin flag) are untouched, and the
# Linux branch of the frame switch (`{frame:!1,autoHideMenuBar:!0}`) still
# applies. Fixes #36.
#
# Usage: linux-hub-focusable.sh [path-to-.webpack/main/index.js]
#===============================================================================
set -uo pipefail

BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
	# default to the in-repo extracted bundle
	BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	BUNDLE="$BUNDLE/extract/app/.webpack/main/index.js"
fi

if [[ ! -f "$BUNDLE" ]]; then
	echo "ERROR: bundle not found: $BUNDLE" >&2
	exit 1
fi

# --- Idempotency guard --------------------------------------------------------
LINUX_MARKER="WISPR_LINUX_HUB_FOCUSABLE"
if grep -q "$LINUX_MARKER" "$BUNDLE"; then
	echo "Already patched ($LINUX_MARKER present in $BUNDLE) - nothing to do."
	exit 0
fi

# --- Backup -------------------------------------------------------------------
if [[ ! -f "$BUNDLE.orig" ]]; then
	cp -p "$BUNDLE" "$BUNDLE.orig"
	echo "Backup written: $BUNDLE.orig"
fi

# --- Patch --------------------------------------------------------------------
python3 - "$BUNDLE" "$LINUX_MARKER" <<'PY'
import sys, io, re
path, marker = sys.argv[1], sys.argv[2]
with io.open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
    data = f.read()

# Anchor: the hub preload path, then (still inside the webPreferences object,
# so no `;`, `{` or `}` may be crossed) the close of webPreferences and the
# focusable:!1 that ends the window config.
anchor = re.compile(
    r'(?P<head>"hub","preload\.js"\)[^;{}]*\},focusable:)!1\}'
)
matches = list(anchor.finditer(data))
if len(matches) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 Hub window config with focusable:!1, "
        f"found {len(matches)}. The bundle layout may have changed; "
        f"inspect manually around `\"hub\",\"preload.js\"`."
    )

def rewrite(m):
    return (m.group('head') + '/*' + marker + '*/'
            '"linux"===process.platform}')

data, n = anchor.subn(rewrite, data, count=1)
if n != 1:
    sys.exit(f"ERROR: substitution applied {n} times (expected 1).")

with io.open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(data)
print("Patched: Hub window config focusable:!1 -> focusable on Linux (1 site).")
PY
status=$?
if [[ $status -ne 0 ]]; then
	echo "ERROR: patch step failed (exit $status). Restoring backup." >&2
	cp -p "$BUNDLE.orig" "$BUNDLE"
	exit 1
fi

# --- Verify the result --------------------------------------------------------
if ! grep -q "$LINUX_MARKER" "$BUNDLE"; then
	echo "ERROR: post-patch verification failed (marker not found)." >&2
	echo "       Restoring backup." >&2
	cp -p "$BUNDLE.orig" "$BUNDLE"
	exit 1
fi

# The marker must sit on the focusable property (proves we hit the Hub config).
if ! grep -q 'focusable:/\*'"$LINUX_MARKER"'\*/"linux"===process.platform}' "$BUNDLE"; then
	echo "ERROR: marker not on the Hub focusable property. Restoring backup." >&2
	cp -p "$BUNDLE.orig" "$BUNDLE"
	exit 1
fi

# Syntax-check: catch a replacement that serializes but doesn't parse before it
# ever reaches asar.
if command -v node >/dev/null; then
	if ! node --check "$BUNDLE"; then
		echo "ERROR: node --check failed on patched bundle. Restoring backup." >&2
		cp -p "$BUNDLE.orig" "$BUNDLE"
		exit 1
	fi
	echo "node --check OK"
fi

echo "OK: Hub window is focusable on Linux in $BUNDLE"
echo
echo "Patched Hub config now does (conceptually):"
echo "  new BrowserWindow({ title: 'Flow Hub', resizable: true, movable: true,"
echo "                      ..., focusable: process.platform === 'linux' })"
echo
echo "So on Linux the Hub is a normal managed top-level window (X11 gets no"
echo "override-redirect), while macOS keeps its non-activating accessory Hub."
