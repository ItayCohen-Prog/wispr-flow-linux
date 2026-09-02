#!/usr/bin/env bash
#===============================================================================
# linux-tray-click.sh -- make a left-click on the tray icon open the Flow Hub
# on Linux, in the Wispr Flow main bundle (.webpack/main/index.js).
#
# WHY THIS PATCH EXISTS
# ---------------------
# Wispr Flow builds its tray icon with `new Tray(icon)`, `setToolTip(...)` and
# `setContextMenu(menu)` and registers NO `click` handler. On macOS the menu
# bar item pops its menu on click natively, so upstream never needed one.
#
# On Linux Electron publishes the tray as a StatusNotifierItem with
# `ItemIsMenu=false` (Chromium hardcodes it), so spec-following hosts (waybar,
# KDE Plasma, omarchy-shell/quickshell) send `Activate` on left-click. Chromium
# maps Activate -> Tray 'click', which nobody listens to: the click is a silent
# no-op and the Hub is only reachable via right-click -> "Open Wispr Flow".
# GNOME's AppIndicator extension opens the menu on left-click regardless, which
# is why the GNOME VM matrix never showed it.
#
# THE PATCH (surgical, one insertion)
# -----------------------------------
# Right after the tray is constructed, add -- on Linux only -- a 'click' handler
# whose body is the SAME code the context menu's "Open Wispr Flow" item runs:
#
#   const n=new r.Tray(t);n.setToolTip("Wispr Flow");
#     becomes
#   const n=new r.Tray(t);n.setToolTip("Wispr Flow");
#   "linux"===process.platform&&n.on("click",()=>{/*WISPR_LINUX_TRAY_CLICK*/
#     (0,N.$5)("tray","open_main_window"),(0,N.CM)(u.z6.Home)});
#
# Anchors are developer strings that survive minification, each unique in the
# 1.6.7 bundle:
#   * `.setToolTip("Wispr Flow")` immediately preceded by
#     `const <n>=new <r>.Tray(<t>);` -- pins the tray factory and captures the
#     tray variable <n>.
#   * `{label:"Open Wispr Flow",click:()=>{<body>}}` whose <body> contains the
#     analytics tuple `"tray","open_main_window"` -- the TRAY menu item, not the
#     macOS dock item (which reports "dock" and is a one-expression arrow).
#     <body> is copied verbatim, so the minified helper names it references are
#     derived from the bundle, never hardcoded.
#
# Safety checks: both anchors must occur exactly once; both must sit in the
# same webpack module (so the copied names resolve to the same bindings); and
# the copied body must not reference the tray variable's own name (which the
# factory's local scope would shadow).
#
# Usage: linux-tray-click.sh [path-to-.webpack/main/index.js]
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
LINUX_MARKER="WISPR_LINUX_TRAY_CLICK"
if grep -q "$LINUX_MARKER" "$BUNDLE"; then
	echo "Already patched ($LINUX_MARKER present in $BUNDLE) - nothing to do."
	exit 0
fi

# --- Backup -------------------------------------------------------------------
if [[ ! -f "$BUNDLE.orig" ]]; then
	cp -p "$BUNDLE" "$BUNDLE.orig"
	echo "Backup written: $BUNDLE.orig"
fi

# --- Patch (tray var + click body DERIVED, not hardcoded) ---------------------
python3 - "$BUNDLE" "$LINUX_MARKER" <<'PY'
import sys, io, re
path, marker = sys.argv[1], sys.argv[2]
with io.open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
    data = f.read()

# Site 1: the tray factory. Capture the tray variable.
#   const <n>=new <r>.Tray(<t>);<n>.setToolTip("Wispr Flow");
tray_re = re.compile(
    r'const\s+(?P<tray>[\w$]+)=new\s+[\w$]+\.Tray\([\w$]+\);'
    r'(?P=tray)\.setToolTip\("Wispr Flow"\);'
)
trays = list(tray_re.finditer(data))
if len(trays) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 tray factory site "
        f"(new Tray + setToolTip(\"Wispr Flow\")), found {len(trays)}. "
        f"The bundle layout may have changed; inspect manually."
    )

# Site 2: the tray context-menu item that opens the Hub. Capture its body.
#   {label:"Open Wispr Flow",click:()=>{<body>}}
#   where <body> contains "tray","open_main_window"
item_re = re.compile(
    r'\{label:"Open Wispr Flow",click:\(\)=>\{'
    r'(?P<body>[^{}]*?"tray","open_main_window"[^{}]*?)'
    r'\}\}'
)
items = list(item_re.finditer(data))
if len(items) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 tray \"Open Wispr Flow\" menu item, "
        f"found {len(items)}. The bundle layout may have changed."
    )

tray_m, item_m = trays[0], items[0]
tray, body = tray_m.group('tray'), item_m.group('body')

# Both sites must be in the same webpack module, or the copied body's minified
# names would resolve to different (or no) bindings at the tray site.
lo, hi = sorted((tray_m.start(), item_m.start()))
if '{"use strict";' in data[lo:hi]:
    sys.exit("ERROR: tray factory and menu item are in different modules; "
             "the copied click body would not resolve. Re-audit the bundle.")

# The body must not use the tray variable's name as an identifier: the factory
# scope shadows it and the copied code would silently target the tray object.
if re.search(r'(?<![\w$.])' + re.escape(tray) + r'(?![\w$])', body):
    sys.exit(f"ERROR: menu body references {tray!r}, which the tray factory "
             f"shadows. Re-audit the bundle.")

# Build with concatenation so no `$N`/`$&` in the body is ever interpreted.
handler = (
    '"linux"===process.platform&&' + tray + '.on("click",()=>{'
    '/*' + marker + '*/' + body + '});'
)
data = data[:tray_m.end()] + handler + data[tray_m.end():]

with io.open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(data)
print(f"Patched: tray var={tray!r}; click handler body copied from the "
      f"\"Open Wispr Flow\" menu item ({len(body)} chars).")
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

# The handler must sit right after the tooltip call (proves we hit the factory).
if ! grep -q 'setToolTip("Wispr Flow");"linux"===process.platform&&[[:alnum:]_$]*\.on("click",()=>{/\*'"$LINUX_MARKER"'\*/' "$BUNDLE"; then
	echo "ERROR: marker not adjacent to the tray factory. Restoring backup." >&2
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

echo "OK: Linux tray left-click handler added in $BUNDLE"
echo
echo "Patched tray setup now does (conceptually):"
echo "  const tray = new Tray(icon); tray.setToolTip('Wispr Flow');"
echo "  if (process.platform === 'linux')"
echo "    tray.on('click', () => openMainWindow('tray')); // as the menu item"
echo
echo "So a left-click (SNI Activate) on the tray icon opens the Flow Hub on"
echo "Linux, matching what right-click -> 'Open Wispr Flow' already did."
