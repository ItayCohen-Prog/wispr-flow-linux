#!/usr/bin/env bash
#===============================================================================
# linux-native-flowbar.sh -- mirror the Flow Bar status IPC over a Unix socket
# so a native shell (omarchy-shell / Quickshell layer-shell plugin) can draw
# the Flow Bar instead of Electron's transparent status window. Patches the
# Wispr Flow main bundle (.webpack/main/index.js).
#
# WHY THIS PATCH EXISTS
# ---------------------
# The Flow Bar is a transparent, always-on-top Electron BrowserWindow ("Flow
# Status Indicator") whose renderer ALSO owns microphone capture. On native
# Wayland an Electron window cannot position itself or shape its input region,
# so the launcher pins the app to XWayland and linux-flowbar-shape.sh crops the
# X11 surface. That costs a single, X11-wide device scale (wrong on mixed-DPI
# setups) and an unmanaged Hub. A layer-shell surface anchored to the bottom
# of the focused monitor is what the bar has been emulating all along.
#
# THE PATCH (one insertion, inert unless enabled)
# ----------------------------------------------
# Right after the status window is constructed we add, gated on
# WISPR_NATIVE_FLOWBAR=1 in the app's environment:
#
#   * a reconnecting `net` client to $WISPR_FLOWBAR_SOCKET (default
#     $XDG_RUNTIME_DIR/wispr-flow/flowbar.sock), newline-delimited JSON,
#     announcing {"t":"hello","p":{resourcesPath,pid}} on every connect so
#     the shell can load the packaged English string table;
#   * a wrapper around statusWindow.webContents.send that mirrors every
#     `status:*` / `notification:*` message as {"t":channel,"p":payload};
#   * an inbound path: lines {"t":channel,"p":payload} whose channel is one of
#     status:startClicked / status:stopClicked / status:cancelClicked /
#     notification:callback are re-emitted on ipcMain, exactly as if the
#     hidden renderer had sent them;
#   * no-op `show`/`showInactive` (and the __wisprShowInactive/__wisprShow
#     slots linux-flowbar-shape.sh keys on) so the Electron window is never
#     mapped: the hidden renderer keeps recording audio, the shell draws.
#
# Without the env var the inserted block is skipped entirely, so XWayland
# builds behave exactly as before.
#
# Anchor: the only BrowserWindow whose preload path contains
# `"status","preload.js"` and whose config carries
# `title:"Flow Status Indicator"`, i.e.
#   const <w>=new <el>.BrowserWindow({...});
# We capture <w> (the window var) and <el> (the electron module var) from the
# match and insert after the closing `});`. Count asserted at exactly 1.
#
# Usage: linux-native-flowbar.sh [path-to-.webpack/main/index.js]
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
LINUX_MARKER="WISPR_LINUX_NATIVE_FLOWBAR"
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

# Anchor: the status-window construction. `[^;]` keeps us inside the single
# `<w>=new X.BrowserWindow({...});` statement (the window var follows a `const`
# or a comma in the minified declaration list; the config object has no
# semicolons; the next statement `let r;n.loadURL(...)` starts after it).
anchor = re.compile(
    r'(?<![\w$])(?P<w>[\w$]+)=new\s+(?P<el>[\w$]+)\.BrowserWindow\(\{'
    r'[^;]*?"status","preload\.js"\)'
    r'[^;]*?title:"Flow Status Indicator"'
    r'[^;]*?\}\);'
)
matches = list(anchor.finditer(data))
if len(matches) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 status-window creation site "
        f"(\"status\",\"preload.js\" + title:\"Flow Status Indicator\"), "
        f"found {len(matches)}. The bundle layout may have changed."
    )
m = matches[0]
w, el = m.group('w'), m.group('el')

# The injected block, one line (the bundle is minified). Built by
# concatenation; no `$N`/`$&` sequences reach a replacement DSL.
bridge = (
    '/*' + marker + '*/'
    'if("1"===process.env.WISPR_NATIVE_FLOWBAR){'
    'const __nf=globalThis.__wisprNativeFlowBar||(globalThis.__wisprNativeFlowBar=(()=>{'
    'const net=require("net"),path=process.env.WISPR_FLOWBAR_SOCKET||'
    '((process.env.XDG_RUNTIME_DIR||"/tmp")+"/wispr-flow/flowbar.sock");'
    'const st={sock:null,connected:false,queue:[],onLine:null};'
    'const connect=()=>{const s=net.createConnection({path});let buf="";'
    's.on("connect",()=>{st.sock=s;st.connected=true;'
    's.write(JSON.stringify({t:"hello",p:{resourcesPath:process.resourcesPath,'
    'pid:process.pid}})+"\\n");'
    'for(const l of st.queue.splice(0))s.write(l)});'
    's.on("data",d=>{buf+=d.toString("utf8");let i;'
    'while((i=buf.indexOf("\\n"))>=0){const l=buf.slice(0,i);buf=buf.slice(i+1);'
    'if(l.trim()&&st.onLine)try{st.onLine(JSON.parse(l))}catch(e){}}});'
    'const drop=()=>{if(st.sock===s){st.sock=null;st.connected=false}'
    'setTimeout(connect,2000).unref()};'
    's.on("error",drop);s.on("close",drop)};'
    'connect();'
    'return{send:o=>{const l=JSON.stringify(o)+"\\n";'
    'st.connected&&st.sock?st.sock.write(l):(st.queue.length<50&&st.queue.push(l))},'
    'setOnLine:f=>{st.onLine=f},get connected(){return st.connected}};})());'
    'const __send=' + w + '.webContents.send.bind(' + w + '.webContents);'
    + w + '.webContents.send=(ch,...a)=>{'
    'if("string"==typeof ch&&(ch.startsWith("status:")||ch.startsWith("notification:")))'
    '__nf.send({t:ch,p:a.length>1?a:a[0]});'
    'return __send(ch,...a)};'
    '__nf.setOnLine(m=>{const ok=["status:startClicked","status:stopClicked",'
    '"status:cancelClicked","notification:callback"];'
    'm&&ok.includes(m.t)&&' + el + '.ipcMain.emit(m.t,{sender:' + w + '.webContents},m.p)});'
    'const __noop=()=>{};'
    + w + '.__wisprShowInactive=__noop;' + w + '.__wisprShow=__noop;'
    + w + '.showInactive=__noop;' + w + '.show=__noop;'
    '}'
)
data = data[:m.end()] + bridge + data[m.end():]

with io.open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(data)
print(f"Patched: status window var={w!r}, electron module={el!r}; "
      f"native Flow Bar bridge inserted (1 site).")
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

# The bridge must follow the status-window construction (proves the site).
if ! grep -q '});/\*'"$LINUX_MARKER"'\*/if("1"===process.env.WISPR_NATIVE_FLOWBAR){' "$BUNDLE"; then
	echo "ERROR: marker not adjacent to the status window. Restoring backup." >&2
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

echo "OK: native Flow Bar bridge inserted in $BUNDLE"
echo
echo "With WISPR_NATIVE_FLOWBAR=1 the app now (conceptually):"
echo "  mirrors status:* / notification:* IPC to \$WISPR_FLOWBAR_SOCKET,"
echo "  accepts status:{start,stop,cancel}Clicked back from the socket,"
echo "  and never maps the Electron status window (the shell draws the bar)."
echo "Without the variable the block is skipped and nothing changes."
