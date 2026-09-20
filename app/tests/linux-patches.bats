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
