#!/usr/bin/env bats
#
# linux-patches.bats
# Unit tests for the four renderer/main bundle patches added for the Linux port:
#   * linux-renderer-chrome.sh           -> remaps the <html> platform class linux->win32
#   * linux-window-frame.sh              -> frameless hub/settings window on Linux
#   * linux-renderer-treat-as-windows.sh -> widens each renderer's isWindows bind
#                                           (bridge stays honest; no preload touched)
#   * linux-deeplink.sh                  -> cold-start wispr-flow: argv parse on Linux
#   * linux-tray-click.sh                -> tray left-click (SNI Activate) opens the Hub
#   * linux-hub-focusable.sh             -> Hub focusable on Linux (no override-redirect)
#   * linux-native-flowbar.sh            -> status IPC mirrored to the shell socket
#
# The real bundle is the proprietary, gitignored app -- not available in CI -- so
# each test drives a hermetic minified-JS FIXTURE carrying the exact anchor the
# patch keys on. Every patch is asserted to: apply (marker + transformation),
# leave unrelated sites alone, produce parseable JS (node --check, skipped if
# node is absent), be idempotent (second run is a no-op, byte-identical), and
# bail non-zero on a fixture whose anchor is absent (never silently no-op).
#

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/../scripts/patches"

setup() {
	TEST_TMP=$(mktemp -d)
	export TEST_TMP
	FIX="$TEST_TMP/bundle.js"
	export FIX
}

teardown() {
	if [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]]; then
		rm -rf "$TEST_TMP"
	fi
}

# node --check the fixture, but only if node is installed (it is in the build
# env; a bare bats runner may lack it).
node_check() {
	if command -v node >/dev/null; then
		node --check "$1"
	fi
}

# Parse the JavaScript string that the Flow Bar patch sends to
# webContents.executeJavaScript. node --check only parses the outer template
# literal; this catches escaping errors inside the runtime renderer program.
node_check_flowbar_renderer() {
	command -v node >/dev/null || return 0
	node - "$1" <<'NODE'
const fs = require("fs");
const source = fs.readFileSync(process.argv[2], "utf8");
const marker = source.indexOf("WISPR_LINUX_FLOWBAR_CROPPED_SURFACE");
if (marker < 0) throw new Error("Flow Bar marker missing");
const start = source.lastIndexOf("`", marker);
const end = source.indexOf("`", marker);
const template = source.slice(start, end + 1);
const rendererProgram = Function(`return ${template}`)();
Function(`return ${rendererProgram}`);
NODE
}

# Assert a second run is a no-op and the file is byte-identical to the first run.
assert_idempotent() {
	local script="$1" target="$2" before after
	before=$(md5sum "$target" | cut -d' ' -f1)
	run bash "$script" "$target"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *lready\ patched* ]]
	after=$(md5sum "$target" | cut -d' ' -f1)
	[[ "$before" == "$after" ]]
}

# =============================================================================
# linux-renderer-chrome.sh
# =============================================================================

@test "chrome: remaps every classList.add(...platform.os) site, leaves others" {
	cat > "$FIX" <<'JS'
document.documentElement.classList.add(window.electron.platform.os);
function f(el){el.classList.add(window.electron.platform.os)}
requestAnimationFrame(()=>x.classList.add(Yw.animated));
JS
	run bash "$PATCH_DIR/linux-renderer-chrome.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -q 'WISPR_LINUX_WIN32_CHROME' "$FIX"
	# both platform.os sites became a linux->win32 ternary
	[[ "$(grep -c '"linux"===window.electron.platform.os?"win32"' "$FIX")" -eq 2 ]]
	# the unrelated animated site is untouched
	grep -qF 'classList.add(Yw.animated)' "$FIX"
	node_check "$FIX"
}

@test "chrome: idempotent on second run" {
	cat > "$FIX" <<'JS'
document.documentElement.classList.add(window.electron.platform.os);
JS
	bash "$PATCH_DIR/linux-renderer-chrome.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-renderer-chrome.sh" "$FIX"
}

@test "chrome: bails non-zero when the anchor is absent" {
	cat > "$FIX" <<'JS'
requestAnimationFrame(()=>x.classList.add(Yw.animated));
JS
	run bash "$PATCH_DIR/linux-renderer-chrome.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	! grep -q 'WISPR_LINUX_WIN32_CHROME' "$FIX"
}

# =============================================================================
# linux-window-frame.sh
# =============================================================================

@test "window-frame: widens the win32 hidden-titlebar predicate to include linux" {
	# The 1.5.695 mac branch dropped "hiddenInset" -- it now sets
	# {frame:!1,titleBarStyle:"hidden",trafficLightPosition,...}. The anchor no
	# longer keys on the mac branch, only on the win32 predicate + hidden assign.
	cat > "$FIX" <<'JS'
var s={tD:false},t={};
s.tD?Object.assign(t,{frame:!1,titleBarStyle:"hidden",trafficLightPosition:{x:1e4,y:10},transparent:!0,hasShadow:!0}):"win32"===process.platform&&Object.assign(t,{titleBarStyle:"hidden",autoHideMenuBar:!0});
JS
	run bash "$PATCH_DIR/linux-window-frame.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -q 'WISPR_LINUX_FRAMELESS' "$FIX"
	grep -qF '"win32"===process.platform||"linux"===process.platform' "$FIX"
	# the mac branch is left untouched
	grep -qF 'trafficLightPosition:{x:1e4,y:10}' "$FIX"
	node_check "$FIX"
}

@test "window-frame: idempotent on second run" {
	cat > "$FIX" <<'JS'
var s={tD:false},t={};
s.tD?Object.assign(t,{frame:!1,titleBarStyle:"hidden",trafficLightPosition:{x:1e4,y:10},transparent:!0,hasShadow:!0}):"win32"===process.platform&&Object.assign(t,{titleBarStyle:"hidden",autoHideMenuBar:!0});
JS
	bash "$PATCH_DIR/linux-window-frame.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-window-frame.sh" "$FIX"
}

@test "window-frame: bails non-zero when no matching window config exists" {
	cat > "$FIX" <<'JS'
var t={};Object.assign(t,{titleBarStyle:"default"});
JS
	run bash "$PATCH_DIR/linux-window-frame.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	! grep -q 'WISPR_LINUX_FRAMELESS' "$FIX"
}

# =============================================================================
# linux-renderer-treat-as-windows.sh
# =============================================================================

@test "treat-as-windows: widens the isWindows bind to include linux, honest bridge" {
	cat > "$FIX" <<'JS'
const y="undefined"!=typeof window?window.electron:void 0,$=y?.platform?.isMacOS??!1,x=y?.platform?.isWindows??!1,k="2025-03-01";
const na=x?Yi:Li,delay=x?500:100;
JS
	run bash "$PATCH_DIR/linux-renderer-treat-as-windows.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -q 'WISPR_LINUX_RENDERER_ISWIN' "$FIX"
	# the bind is widened, reusing the SAME window.electron local (y) for the OS check
	grep -qF 'x=((y?.platform?.isWindows??!1)||"linux"===y?.platform?.os)/*WISPR_LINUX_RENDERER_ISWIN*/' "$FIX"
	# isMacOS bind is untouched; the bridge property name itself is never flipped
	grep -qF '$=y?.platform?.isMacOS??!1' "$FIX"
	# downstream consumers (na, delay) are left exactly as-is -- they ride on x
	grep -qF 'na=x?Yi:Li' "$FIX"
	grep -qF 'delay=x?500:100' "$FIX"
	node_check "$FIX"
}

@test "treat-as-windows: idempotent on second run" {
	cat > "$FIX" <<'JS'
const y=window.electron,$=y?.platform?.isMacOS??!1,x=y?.platform?.isWindows??!1;
JS
	bash "$PATCH_DIR/linux-renderer-treat-as-windows.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-renderer-treat-as-windows.sh" "$FIX"
}

@test "treat-as-windows: bails non-zero when the renderer has no isWindows bind" {
	cat > "$FIX" <<'JS'
const y=window.electron,$=y?.platform?.isMacOS??!1;
JS
	run bash "$PATCH_DIR/linux-renderer-treat-as-windows.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	! grep -q 'WISPR_LINUX_RENDERER_ISWIN' "$FIX"
}

# =============================================================================
# linux-deeplink.sh
# =============================================================================

@test "deeplink: widens the cold-start win32 argv guard to include linux" {
	cat > "$FIX" <<'JS'
function L(x){}function B(x){return x}
if(f.H8){const e=B(process.argv.find(e=>e.startsWith("wispr-flow:")||e.startsWith("wispr-flow/")));e&&L(e)}
JS
	run bash "$PATCH_DIR/linux-deeplink.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -q 'WISPR_LINUX_DEEPLINK' "$FIX"
	grep -qF 'if(f.H8||"linux"===process.platform){' "$FIX"
	node_check "$FIX"
}

@test "deeplink: idempotent on second run" {
	cat > "$FIX" <<'JS'
function L(x){}function B(x){return x}
if(f.H8){const e=B(process.argv.find(e=>e.startsWith("wispr-flow:")||e.startsWith("wispr-flow/")));e&&L(e)}
JS
	bash "$PATCH_DIR/linux-deeplink.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-deeplink.sh" "$FIX"
}

@test "deeplink: leaves the cross-platform second-instance handler untouched" {
	# second-instance scans r.find(...), NOT process.argv.find(...) -- the anchor
	# must not match it, so the patch must bail (0 cold-start guards present).
	cat > "$FIX" <<'JS'
function L(x){}function B(x){return x}
app.on("second-instance",(e,r)=>{if(f.H8){const u=B(r.find(e=>e.startsWith("wispr-flow:")));u&&L(u)}});
JS
	run bash "$PATCH_DIR/linux-deeplink.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	! grep -q 'WISPR_LINUX_DEEPLINK' "$FIX"
}

# =============================================================================
# linux-flowbar-shape.sh (physical surface cropping)
# =============================================================================

write_flowbar_fixture() {
	cat > "$FIX" <<'JS'
const q=()=>{const n=new BrowserWindow({show:!1,transparent:!0});n.setIgnoreMouseEvents(!0,{forward:!0}),n.webContents.on("before-mouse-event",(e,t)=>{if("mouseDown"===t.type){const e=n.getBounds(),r=`event: ${t.x}, ${t.y}`,i=m.i0?`lastAlphaCheck: {cursor: (${m.i0.cursorPos.x}, ${m.i0.cursorPos.y}), BGRA: [${m.i0.bitmap.join(", ")}], alpha: ${m.i0.alpha}, age: ${Date.now()-m.i0.timestamp}ms}`:"lastAlphaCheck: null";a().warn(`[StatusWindow] Mouse input received - type: ${t.type}, bounds: ${JSON.stringify(e)}, visible: ${n.isVisible()}, event coords: ${r}, ${i}`)}});return n};
let P,W,F=!1,U=!1;
const $=()=>{const e=(D.RA.statusWindow&&!D.RA.statusWindow.isDestroyed()||(a().error("Tried to show/hide status window, but it was destroyed. Rebuilding."),D.RA.statusWindow=q()),D.RA.statusWindow);Array.from([P,W]).forEach(e=>(0,O.iM)(e)),P=te(),G(e),b.H8&&e.setAlwaysOnTop(!0,"screen-saver"),e.showInactive(),a().info("Showing status window")},H=()=>{Array.from([P,W]).forEach(e=>(0,O.iM)(e)),D.RA.statusWindow&&D.RA.statusWindow.destroy()};let V=!1;
const G=e=>{V||((0,O.iM)(W),W=(0,m.Bi)(e))},Y=()=>{V||(V=!0,(0,O.iM)(W),D.RA.statusWindow&&!D.RA.statusWindow.isDestroyed()&&D.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0}),a().info("[Status] Alpha hit-test poll suspended for feature tour"))},K=()=>{V&&(V=!1,D.RA.statusWindow&&!D.RA.statusWindow.isDestroyed()?G(D.RA.statusWindow):(0,O.iM)(W),a().info("[Status] Alpha hit-test poll resumed after feature tour"))};
const handlers=()=>{(0,T.Z4)(y.EB.BarHidden,!1,()=>{(0,O.iM)(W),D.RA.statusWindow?.setIgnoreMouseEvents(!0)}),(0,T.Z4)(y.EB.BarVisible,!1,()=>{G(D.RA.statusWindow)}),(0,T.Z4)(y.K4.EnableMouseEvents,!1,e=>{V||(D.RA.statusWindow?.setIgnoreMouseEvents(!e,{forward:!0}),e&&G(D.RA.statusWindow))})};
async function genericAlpha(e,t,r,l){const n={x:r.x-l.x,y:r.y-l.y,width:1,height:1},i=await e.webContents.capturePage(n),s=i.toBitmap(),o=s[3]??0;m.i0={cursorPos:{...r},winRect:{...l},bitmap:Array.from(s.subarray(0,4)),alpha:o,timestamp:Date.now()},e.setIgnoreMouseEvents(o<=t,{forward:!0})}
JS
}

@test "flowbar-crop: physically crops the OS surface to visible DOM" {
	write_flowbar_fixture
	run bash "$PATCH_DIR/linux-flowbar-shape.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -qF 'WISPR_LINUX_FLOWBAR_CROPPED_SURFACE' "$FIX"
	grep -qF 'webContents.executeJavaScript' "$FIX"
	grep -qF 'document.querySelectorAll("*")' "$FIX"
	grep -qF 'getClientRects' "$FIX"
	grep -qF 'backgroundColor' "$FIX"
	grep -qF 'boxShadow' "$FIX"
	grep -qF 'Node.TEXT_NODE' "$FIX"
	grep -qF '.setBounds(' "$FIX"
	grep -qF '__wisprLogicalWidth=440' "$FIX"
	grep -qF '__wisprLogicalHeight=320' "$FIX"
	grep -qF '__wisprCropX' "$FIX"
	grep -qF '__wisprCrop.width<=64&&__wisprCrop.height<=32' "$FIX"
	grep -qF 'translate(' "$FIX"
	grep -qF '.__wisprShowInactive=' "$FIX"
	grep -qF '.showInactive=()=>{__wisprFlowBarVisible=!0' "$FIX"
	grep -qF '.__wisprShowInactive()' "$FIX"
	grep -qF 'setInterval(' "$FIX"
	grep -qF ',50)' "$FIX"
	# shellcheck disable=SC2314
	! grep -qF 'screen.getCursorScreenPoint' "$FIX"
	# shellcheck disable=SC2314
	! grep -qF '.setShape(' "$FIX"
	# The generic helper remains byte-compatible for non-status windows.
	grep -qF 'capturePage(n)' "$FIX"
	grep -qF 'bitmap:Array.from' "$FIX"
	grep -qF '.bitmap.join(", ")' "$FIX"
	node_check "$FIX"
	node_check_flowbar_renderer "$FIX"
}

@test "flowbar-crop: idle is unmapped and active UI is crop-gated" {
	write_flowbar_fixture
	run bash "$PATCH_DIR/linux-flowbar-shape.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -qF 'e?G(D.RA.statusWindow):(__wisprFlowBarVisible=!1' "$FIX"
	grep -qF '__wisprFlowNotificationVisible=!1' "$FIX"
	grep -qF '__wisprFlowBarVisible=!0' "$FIX"
	grep -qF '__wisprFlowNotificationVisible=!!e' "$FIX"
	grep -qF '__wisprFlowBarVisible=!1' "$FIX"
	grep -qF '__wisprActive=__wisprFlowBarVisible||__wisprFlowNotificationVisible' "$FIX"
	grep -qF '.setFocusable(__wisprFlowNotificationVisible)' "$FIX"
	grep -qF '.hide()' "$FIX"
	grep -qF '.__wisprShowInactive()' "$FIX"
	# shellcheck disable=SC2314
	! grep -qF 'setIgnoreMouseEvents(!e,{forward:!0})' "$FIX"
	# shellcheck disable=SC2314
	! grep -qF 'e.showInactive(),a().info("Showing status window")' "$FIX"
	node_check "$FIX"
}

@test "flowbar-crop: is idempotent on second run" {
	write_flowbar_fixture
	bash "$PATCH_DIR/linux-flowbar-shape.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-flowbar-shape.sh" "$FIX"
}

@test "flowbar-crop: bails non-zero when the status lifecycle is absent" {
	cat > "$FIX" <<'JS'
const unrelated=()=>window.showInactive();
JS
	run bash "$PATCH_DIR/linux-flowbar-shape.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_FLOWBAR_CROPPED_SURFACE' "$FIX"
}

@test "flowbar-crop: bails non-zero when the lifecycle anchor is ambiguous" {
	write_flowbar_fixture
	printf '%s\n' 'const second=e=>{V||((0,O.iM)(W),W=(0,m.Bi)(e))};' >> "$FIX"
	run bash "$PATCH_DIR/linux-flowbar-shape.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_FLOWBAR_CROPPED_SURFACE' "$FIX"
}

# =============================================================================
# linux-tray-click.sh
# =============================================================================

write_tray_fixture() {
	cat > "$FIX" <<'JS'
const P=async()=>{const q=[{label:"Open Wispr Flow",click:()=>{(0,N.$5)("tray","open_main_window"),(0,N.CM)(u.z6.Home)}},{type:"separator"},{role:"quit"}];return{menu:r.Menu.buildFromTemplate(q),title:""}};
const Q=async()=>{const e="TrayIconWindows.png",t=r.nativeImage.createFromPath(e);const n=new r.Tray(t);n.setToolTip("Wispr Flow");const{menu:i,title:c}=await P();return n.setContextMenu(i),n};
N=()=>{};N.$5=()=>{};N.CM=()=>{};u={z6:{Home:"Home"}};r={};
JS
}

@test "tray-click: adds a linux click handler with the menu item's body" {
	write_tray_fixture
	run bash "$PATCH_DIR/linux-tray-click.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -qF 'WISPR_LINUX_TRAY_CLICK' "$FIX"
	grep -qF 'n.setToolTip("Wispr Flow");"linux"===process.platform&&n.on("click",()=>{/*WISPR_LINUX_TRAY_CLICK*/(0,N.$5)("tray","open_main_window"),(0,N.CM)(u.z6.Home)});const{menu:i,title:c}=await P();' "$FIX"
	# The menu item itself is untouched.
	grep -qF '{label:"Open Wispr Flow",click:()=>{(0,N.$5)("tray","open_main_window"),(0,N.CM)(u.z6.Home)}}' "$FIX"
	node_check "$FIX"
}

@test "tray-click: idempotent on second run" {
	write_tray_fixture
	bash "$PATCH_DIR/linux-tray-click.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-tray-click.sh" "$FIX"
}

@test "tray-click: ignores the macOS dock item, bails when the tray item is absent" {
	# The dock menu reports "dock" and is a one-expression arrow: no match, so
	# the patch must bail (0 tray items) rather than copy the wrong body.
	cat > "$FIX" <<'JS'
const N=()=>{e.push({label:"Open Wispr Flow",click:()=>S("dock","open_main_window",d.z6.Home)})};
const Q=async()=>{const n=new r.Tray(t);n.setToolTip("Wispr Flow");return n};
JS
	run bash "$PATCH_DIR/linux-tray-click.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_TRAY_CLICK' "$FIX"
}

@test "tray-click: bails when the tray factory anchor is absent" {
	cat > "$FIX" <<'JS'
const q=[{label:"Open Wispr Flow",click:()=>{(0,N.$5)("tray","open_main_window"),(0,N.CM)(u.z6.Home)}}];
JS
	run bash "$PATCH_DIR/linux-tray-click.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_TRAY_CLICK' "$FIX"
}

@test "tray-click: bails when the two sites live in different modules" {
	cat > "$FIX" <<'JS'
1(e,t,n){"use strict";const q=[{label:"Open Wispr Flow",click:()=>{(0,N.$5)("tray","open_main_window"),(0,N.CM)(u.z6.Home)}}]}
2(e,t,n){"use strict";const Q=async()=>{const n=new r.Tray(t);n.setToolTip("Wispr Flow");return n}}
JS
	run bash "$PATCH_DIR/linux-tray-click.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_TRAY_CLICK' "$FIX"
}

# =============================================================================
# linux-hub-focusable.sh
# =============================================================================

write_hub_fixture() {
	cat > "$FIX" <<'JS'
const se=()=>{const e=(0,o.Rj)(_.PF),t={title:"Flow Hub",width:e.width,height:e.height,center:!0,resizable:!0,movable:!0,maximizable:!0,fullscreenable:!0,show:!1,transparent:_.tD,hasShadow:!0,webPreferences:{...O.g,preload:require("path").resolve(__dirname,"../renderer","hub","preload.js"),devTools:"development"===_.M0||(0,N.Pv)(d.RA.prefs?.user.email||"")},focusable:!1};_.tD?Object.assign(t,{frame:!1,titleBarStyle:"hidden"}):Object.assign(t,{frame:!1,autoHideMenuBar:!0});const n=new i.BrowserWindow(t);return n};
const ov=()=>new r.BrowserWindow({transparent:!0,frame:!1,hasShadow:!1,focusable:!1,skipTaskbar:!0,resizable:!1});
JS
}

@test "hub-focusable: makes only the Hub window focusable on linux" {
	write_hub_fixture
	run bash "$PATCH_DIR/linux-hub-focusable.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -qF 'WISPR_LINUX_HUB_FOCUSABLE' "$FIX"
	grep -qF '"hub","preload.js"),devTools:"development"===_.M0||(0,N.Pv)(d.RA.prefs?.user.email||"")},focusable:/*WISPR_LINUX_HUB_FOCUSABLE*/"linux"===process.platform};_.tD?' "$FIX"
	# The overlay window keeps its focusable:!1.
	grep -qF 'hasShadow:!1,focusable:!1,skipTaskbar:!0' "$FIX"
	node_check "$FIX"
}

@test "hub-focusable: idempotent on second run" {
	write_hub_fixture
	bash "$PATCH_DIR/linux-hub-focusable.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-hub-focusable.sh" "$FIX"
}

@test "hub-focusable: bails non-zero when the Hub config anchor is absent" {
	cat > "$FIX" <<'JS'
const ov=()=>new r.BrowserWindow({transparent:!0,frame:!1,hasShadow:!1,focusable:!1,skipTaskbar:!0});
JS
	run bash "$PATCH_DIR/linux-hub-focusable.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_HUB_FOCUSABLE' "$FIX"
}

# =============================================================================
# linux-native-flowbar.sh
# =============================================================================

write_native_fixture() {
	cat > "$FIX" <<'JS'
const q=()=>{const e=i.screen.getDisplayNearestPoint(i.screen.getCursorScreenPoint()),t=Z(e),n=new i.BrowserWindow({...t,show:!1,webPreferences:{...f.g,preload:require("path").resolve(__dirname,"../renderer","status","preload.js"),backgroundThrottling:!1},transparent:!0,hasShadow:!1,type:b.tD?"panel":"toolbar",title:"Flow Status Indicator",frame:!1,alwaysOnTop:!0});let r;n.loadURL("x"),n.setIgnoreMouseEvents(!0,{forward:!0});return n};
const other=()=>new i.BrowserWindow({title:"Calendar Reminder",frame:!1});
JS
}

@test "native-flowbar: bridges the status window behind an env gate" {
	write_native_fixture
	run bash "$PATCH_DIR/linux-native-flowbar.sh" "$FIX"
	[[ "$status" -eq 0 ]]
	grep -qF 'WISPR_LINUX_NATIVE_FLOWBAR' "$FIX"
	grep -qF 'title:"Flow Status Indicator",frame:!1,alwaysOnTop:!0});/*WISPR_LINUX_NATIVE_FLOWBAR*/if("1"===process.env.WISPR_NATIVE_FLOWBAR){' "$FIX"
	grep -qF 'n.webContents.send=(ch,...a)=>{' "$FIX"
	grep -qF '{t:"hello",p:{resourcesPath:process.resourcesPath,pid:process.pid}}' "$FIX"
	grep -qF 'i.ipcMain.emit(m.t,{sender:n.webContents},m.p)' "$FIX"
	grep -qF 'n.showInactive=__noop;n.show=__noop;' "$FIX"
	# The statement after the window construction is intact.
	grep -qF '}let r;n.loadURL("x")' "$FIX"
	# The unrelated window is untouched.
	grep -qF 'new i.BrowserWindow({title:"Calendar Reminder",frame:!1});' "$FIX"
	node_check "$FIX"
}

@test "native-flowbar: idempotent on second run" {
	write_native_fixture
	bash "$PATCH_DIR/linux-native-flowbar.sh" "$FIX"
	assert_idempotent "$PATCH_DIR/linux-native-flowbar.sh" "$FIX"
}

@test "native-flowbar: bails non-zero when the status window anchor is absent" {
	cat > "$FIX" <<'JS'
const other=()=>new i.BrowserWindow({title:"Calendar Reminder",frame:!1});
JS
	run bash "$PATCH_DIR/linux-native-flowbar.sh" "$FIX"
	[[ "$status" -ne 0 ]]
	# shellcheck disable=SC2314
	! grep -qF 'WISPR_LINUX_NATIVE_FLOWBAR' "$FIX"
}
