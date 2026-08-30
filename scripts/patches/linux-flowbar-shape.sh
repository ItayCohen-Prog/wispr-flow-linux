#!/usr/bin/env bash
#===============================================================================
# linux-flowbar-shape.sh -- physically crop Wispr's XWayland status surface to
# the visible Flow Bar and notifications.
#
# Hyprland 0.56 still routes a mapped XWayland surface ahead of native Wayland
# clients even when XShape reports a tiny input region. Input masks therefore
# cannot make the transparent part of Wispr's 440x320 status window safe. This
# patch keeps a logical 440x320 renderer, translates it into a tightly cropped
# BrowserWindow, and unmaps that window when no status UI is visible.
#
# Usage: linux-flowbar-shape.sh <path-to-.webpack/main/index.js>
#===============================================================================
set -uo pipefail

BUNDLE=${1:-}
if [[ -z $BUNDLE || ! -f $BUNDLE ]]; then
	echo "usage: $0 <path-to-.webpack/main/index.js>" >&2
	exit 2
fi

MARKER='WISPR_LINUX_FLOWBAR_CROPPED_SURFACE'
if grep -qF "$MARKER" "$BUNDLE"; then
	echo "Already patched ($MARKER present in $BUNDLE) - nothing to do."
	exit 0
fi

BACKUP="$BUNDLE.flowbar-shape.orig"
if [[ ! -f $BACKUP ]]; then
	cp -p "$BUNDLE" "$BACKUP" || {
		echo "ERROR: could not create backup: $BACKUP" >&2
		exit 1
	}
	echo "Backup written: $BACKUP"
fi

if ! python3 - "$BUNDLE" "$MARKER" <<'PY'
import io
import re
import sys

path, marker = sys.argv[1:]
with io.open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
    data = handle.read()

state = re.compile(r"let\s+(?P<timers>[\w$]+,[\w$]+),F=!1,U=!1;")
state_matches = list(state.finditer(data))
if len(state_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 status lifecycle state declaration, "
        f"found {len(state_matches)}. Re-audit the Wispr main bundle."
    )
state_match = state_matches[0]

start = re.compile(
    r"const\s+(?P<start>[\w$]+)=(?P<arg>[\w$]+)=>\{"
    r"(?P<suspended>[\w$]+)\|\|\("
    r"(?P<clear>\(0,(?P<timer_module>[\w$]+)\.(?P<clear_fn>[\w$]+)\)"
    r"\((?P<timer>[\w$]+)\)),"
    r"(?P=timer)="
    r"\(0,(?P<alpha_module>[\w$]+)\.Bi\)\((?P=arg)\)\)\}"
)
start_matches = list(start.finditer(data))
if len(start_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 status alpha-poll starter, "
        f"found {len(start_matches)}. Re-audit the Wispr main bundle."
    )
start_match = start_matches[0]
names = start_match.groupdict()

window = r"(?P<window>[\w$]+\.[\w$]+\.statusWindow)"
bar_hidden = re.compile(
    r"(?P<prefix>\(0,[\w$]+\.[\w$]+\)\("
    r"[\w$]+\.[\w$]+\.BarHidden,!1,\(\)=>\{)"
    + re.escape(names["clear"])
    + r"," + window + r"\?\.setIgnoreMouseEvents\(!0\)(?P<suffix>\}\))"
)
hidden_matches = list(bar_hidden.finditer(data))
if len(hidden_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 Flow Bar hidden handler, "
        f"found {len(hidden_matches)}."
    )
hidden = hidden_matches[0]
window_expr = hidden.group("window")

bar_visible = re.compile(
    r"(?P<prefix>\(0,[\w$]+\.[\w$]+\)\("
    r"[\w$]+\.[\w$]+\.BarVisible,!1,\(\)=>\{)"
    + re.escape(names["start"])
    + r"\(" + re.escape(window_expr) + r"\)(?P<suffix>\}\))"
)
visible_matches = list(bar_visible.finditer(data))
if len(visible_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 Flow Bar visible handler, "
        f"found {len(visible_matches)}."
    )
visible = visible_matches[0]

notification = re.compile(
    r"(?P<prefix>\(0,[\w$]+\.[\w$]+\)\("
    r"[\w$]+\.[\w$]+\.EnableMouseEvents,!1,)"
    r"(?P<arg>[\w$]+)=>\{" + re.escape(names["suspended"]) + r"\|\|\("
    + re.escape(window_expr)
    + r"\?\.setIgnoreMouseEvents\(!(?P=arg),\{forward:!0\}\),"
    r"(?P=arg)&&" + re.escape(names["start"])
    + r"\(" + re.escape(window_expr) + r"\)\)\}"
)
notification_matches = list(notification.finditer(data))
if len(notification_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 notification input handler, "
        f"found {len(notification_matches)}."
    )
notification_match = notification_matches[0]

startup = re.compile(
    r"(?P<monitor>[\w$]+)=(?P<monitor_fn>[\w$]+)\(\),"
    + re.escape(names["start"]) + r"\((?P<window>[\w$]+)\),"
    r"(?P<platform>[\w$]+)\.H8&&(?P=window)\.setAlwaysOnTop"
    r"\(!0,\"screen-saver\"\),(?P=window)\.showInactive\(\),"
    r"(?P<logger>[\w$]+)\(\)\.info\(\"Showing status window\"\)"
)
startup_matches = list(startup.finditer(data))
if len(startup_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 status startup show sequence, "
        f"found {len(startup_matches)}."
    )
startup_match = startup_matches[0]

suspend = re.compile(
    r"(?P<name>[\w$]+)=\(\)=>\{" + re.escape(names["suspended"])
    + r"\|\|\(" + re.escape(names["suspended"]) + r"=!0,"
    + re.escape(names["clear"]) + r"," + re.escape(window_expr)
    + r"&&!" + re.escape(window_expr) + r"\.isDestroyed\(\)&&"
    + re.escape(window_expr)
    + r"\.setIgnoreMouseEvents\(!0,\{forward:!0\}\),"
    r"(?P<logger>[\w$]+)\(\)\.info\("
    r"\"\[Status\] Alpha hit-test poll suspended for feature tour\"\)\)\}"
)
suspend_matches = list(suspend.finditer(data))
if len(suspend_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 feature-tour suspend handler, "
        f"found {len(suspend_matches)}."
    )
suspend_match = suspend_matches[0]

resume = re.compile(
    r"(?P<name>[\w$]+)=\(\)=>\{" + re.escape(names["suspended"])
    + r"&&\(" + re.escape(names["suspended"]) + r"=!1,"
    + re.escape(window_expr) + r"&&!" + re.escape(window_expr)
    + r"\.isDestroyed\(\)\?" + re.escape(names["start"])
    + r"\(" + re.escape(window_expr) + r"\):"
    + re.escape(names["clear"]) + r",(?P<logger>[\w$]+)\(\)\.info\("
    r"\"\[Status\] Alpha hit-test poll resumed after feature tour\"\)\)\}"
)
resume_matches = list(resume.finditer(data))
if len(resume_matches) != 1:
    sys.exit(
        "ERROR: expected exactly 1 feature-tour resume handler, "
        f"found {len(resume_matches)}."
    )
resume_match = resume_matches[0]

crop_program = r'''`(()=>{/*WISPR_LINUX_FLOWBAR_CROPPED_SURFACE*/
const width=440,height=320,cropX=Number(window.__wisprCropX)||0,cropY=Number(window.__wisprCropY)||0,root=document.getElementById("root")||document.body,roots=new Set([document.documentElement,document.body,root]),rects=[],setup=(x,y)=>{window.__wisprCropX=x;window.__wisprCropY=y;for(const e of [document.documentElement,document.body,root])if(e){e.style.setProperty("width",width+"px","important");e.style.setProperty("height",height+"px","important");e.style.setProperty("min-width",width+"px","important");e.style.setProperty("min-height",height+"px","important")}document.documentElement.style.setProperty("overflow","hidden","important");document.body.style.setProperty("overflow","hidden","important");if(root){root.style.setProperty("transform-origin","0 0","important");root.style.setProperty("transform","translate("+(-x)+"px,"+(-y)+"px)","important");const shell=root.firstElementChild;if(shell){shell.style.setProperty("width",width+"px","important");shell.style.setProperty("height",height+"px","important")}}};window.__wisprSetCrop=setup;setup(cropX,cropY);
const hidden=(e,s)=>!e.isConnected||s.display==="none"||s.visibility==="hidden"||s.visibility==="collapse"||Number(s.opacity)===0||typeof e.checkVisibility==="function"&&!e.checkVisibility({checkOpacity:true,checkVisibilityCSS:true}),color=c=>{if(!c||c==="transparent")return!1;if(c.startsWith("rgba(")){const p=c.slice(5,-1).split(",");if(4===p.length&&0===Number(p[3].trim()))return!1}if(c.startsWith("rgb(")&&c.includes("/")){const a=c.slice(c.lastIndexOf("/")+1,-1).trim();if(a==="0"||a==="0%")return!1}return!0},paint=s=>!!s&&(color(s.backgroundColor)||!!s.backgroundImage&&s.backgroundImage!=="none"||!!s.boxShadow&&s.boxShadow!=="none"||!!s.filter&&s.filter!=="none"||s.outlineStyle!=="none"&&parseFloat(s.outlineWidth)>0||["Top","Right","Bottom","Left"].some(k=>parseFloat(s["border"+k+"Width"])>0&&s["border"+k+"Style"]!=="none"&&color(s["border"+k+"Color"]))),pseudo=(e,p)=>{const s=getComputedStyle(e,p);return!!s.content&&s.content!=="none"&&s.content!=="normal"&&paint(s)},push=(r,force=!1)=>{const x=Math.max(0,Math.floor(r.left+cropX)),y=Math.max(0,Math.floor(r.top+cropY)),right=Math.min(width,Math.ceil(r.right+cropX)),bottom=Math.min(height,Math.ceil(r.bottom+cropY));right>x&&bottom>y&&(force||right-x<width-2||bottom-y<height-2)&&rects.push({x,y,width:right-x,height:bottom-y})};
for(const e of document.querySelectorAll("*")){if(roots.has(e))continue;const s=getComputedStyle(e);if(hidden(e,s))continue;const interactive=e.matches("button,a,input,select,textarea,summary,[role=button],[role=link],[role=menuitem],[role=option],[role=checkbox],[role=radio],[tabindex]:not([tabindex=\\"-1\\"])");if(interactive||paint(s)||pseudo(e,"::before")||pseudo(e,"::after")||e.matches("img,svg,canvas,video,picture")||e.closest("svg"))for(const r of e.getClientRects())push(r,interactive);for(const n of e.childNodes)if(n.nodeType===Node.TEXT_NODE&&n.textContent.trim()){const r=document.createRange();r.selectNodeContents(n);for(const t of r.getClientRects())push(t,!0)}}
rects.sort((a,b)=>b.width*b.height-a.width*a.height);const result=[];for(const r of rects)result.some(e=>r.x>=e.x&&r.y>=e.y&&r.x+r.width<=e.x+e.width&&r.y+r.height<=e.y+e.height)||result.push(r);return result})()`'''

arg = names["arg"]
suspended_name = names["suspended"]
clear = names["clear"]
timer = names["timer"]
crop_start = names["start"]

crop_replacement = (
    "const __wisprLogicalWidth=440,__wisprLogicalHeight=320,"
    + "__wisprFlowCropProgram=" + crop_program + ";const "
    + crop_start + "=" + arg + "=>{if(" + suspended_name + ")return;"
    + clear + ";" + arg + ".__wisprShowInactive||(" + arg
    + ".__wisprShowInactive=" + arg + ".showInactive.bind(" + arg + "),"
    + arg + ".__wisprShow=" + arg + ".show.bind(" + arg + ")," + arg
    + ".showInactive=()=>{__wisprFlowBarVisible=!0," + crop_start + "("
    + arg + ")}," + arg + ".show=()=>{__wisprFlowBarVisible=!0,"
    + crop_start + "(" + arg + ")});let "
    + "__wisprLastCrop=\"\",__wisprCropBusy=!1;const "
    + "__wisprApplyCrop=async()=>{if(__wisprCropBusy||!" + arg + "||"
    + arg + ".isDestroyed()||" + arg + ".webContents.isDestroyed()||"
    + arg + ".webContents.isCrashed())return;__wisprCropBusy=!0;try{const "
    + "__wisprActive=__wisprFlowBarVisible||"
    + "__wisprFlowNotificationVisible;if(!__wisprActive)return void "
    + arg + ".hide();const "
    + "__wisprRects=await " + arg
    + ".webContents.executeJavaScript(__wisprFlowCropProgram,!0);"
    + "if(!Array.isArray(__wisprRects))throw new Error(\"Invalid status crop\");"
    + "if(0===__wisprRects.length)return __wisprLastCrop=\"\",void "
    + arg + ".hide();const __wisprPad=6,__wisprLeft=Math.max(0,"
    + "Math.min(...__wisprRects.map(e=>e.x))-__wisprPad),"
    + "__wisprTop=Math.max(0,Math.min(...__wisprRects.map(e=>e.y))-"
    + "__wisprPad),__wisprRight=Math.min(__wisprLogicalWidth,"
    + "Math.max(...__wisprRects.map(e=>e.x+e.width))+__wisprPad),"
    + "__wisprBottom=Math.min(__wisprLogicalHeight,Math.max("
    + "...__wisprRects.map(e=>e.y+e.height))+__wisprPad),"
    + "__wisprCrop={x:__wisprLeft,y:__wisprTop,width:Math.max(1,"
    + "__wisprRight-__wisprLeft),height:Math.max(1,__wisprBottom-"
    + "__wisprTop)};if(__wisprCrop.width<=64&&__wisprCrop.height<=32)"
    + "return __wisprLastCrop=\"\"," + arg + ".hide();const "
    + "__wisprCropKey=JSON.stringify(__wisprCrop);if("
    + "__wisprCropKey===__wisprLastCrop&&" + arg + ".isVisible())return;"
    + "const __wisprBounds=" + arg + ".getBounds(),__wisprPreviousX=Number("
    + arg + ".__wisprCropX)||0,__wisprPreviousY=Number(" + arg
    + ".__wisprCropY)||0;if(!Number.isFinite(" + arg
    + ".__wisprBaseX)||__wisprBounds.width===__wisprLogicalWidth&&"
    + "__wisprBounds.height===__wisprLogicalHeight)" + arg
    + ".__wisprBaseX=__wisprBounds.x-(__wisprBounds.width==="
    + "__wisprLogicalWidth?0:__wisprPreviousX)," + arg
    + ".__wisprBaseY=__wisprBounds.y-(__wisprBounds.height==="
    + "__wisprLogicalHeight?0:__wisprPreviousY);else if(Math.abs("
    + "__wisprBounds.x-(" + arg + ".__wisprBaseX+__wisprPreviousX))>1||"
    + "Math.abs(__wisprBounds.y-(" + arg
    + ".__wisprBaseY+__wisprPreviousY))>1)" + arg
    + ".__wisprBaseX=__wisprBounds.x-__wisprPreviousX," + arg
    + ".__wisprBaseY=__wisprBounds.y-__wisprPreviousY;await " + arg
    + ".webContents.executeJavaScript(\"window.__wisprSetCrop(\"+"
    + "__wisprCrop.x+\",\"+__wisprCrop.y+\")\",!0)," + arg
    + ".__wisprCropX=__wisprCrop.x," + arg
    + ".__wisprCropY=__wisprCrop.y," + arg
    + ".setBounds({x:Math.round(" + arg + ".__wisprBaseX+__wisprCrop.x),"
    + "y:Math.round(" + arg + ".__wisprBaseY+__wisprCrop.y),width:"
    + "__wisprCrop.width,height:__wisprCrop.height},!1)," + arg
    + ".setFocusable(__wisprFlowNotificationVisible)," + arg
    + ".setIgnoreMouseEvents(!1)," + arg
    + ".__wisprShowInactive(),__wisprLastCrop=__wisprCropKey}catch("
    + "__wisprCropError){" + arg + "&&!" + arg + ".isDestroyed()&&"
    + arg
    + ".hide(),console.error(\"[Status] Crop update failed; window hidden\","
    + "__wisprCropError)}finally{__wisprCropBusy=!1}};__wisprApplyCrop(),"
    + timer + "=setInterval(__wisprApplyCrop,50)}"
)

state_replacement = (
    "let " + state_match.group("timers")
    + ",F=!1,U=!1,__wisprFlowBarVisible=!1,"
    + "__wisprFlowNotificationVisible=!1;"
)

startup_window = startup_match.group("window")
startup_replacement = (
    startup_match.group("monitor") + "=" + startup_match.group("monitor_fn")
    + "()," + crop_start + "(" + startup_window + "),"
    + startup_match.group("platform") + ".H8&&" + startup_window
    + ".setAlwaysOnTop(!0,\"screen-saver\"),"
    + startup_match.group("logger")
    + "().info(\"Status window lifecycle initialized\")"
)

hidden_replacement = (
    hidden.group("prefix") + clear + ",__wisprFlowBarVisible=!1,"
    + "__wisprFlowNotificationVisible?" + crop_start + "(" + window_expr
    + "):" + window_expr + "?.hide()" + hidden.group("suffix")
)
visible_replacement = (
    visible.group("prefix") + "__wisprFlowBarVisible=!0," + crop_start
    + "(" + window_expr + ")" + visible.group("suffix")
)
notification_arg = notification_match.group("arg")
notification_replacement = (
    notification_match.group("prefix") + notification_arg + "=>{"
    + suspended_name + "||(__wisprFlowNotificationVisible=!!"
    + notification_arg + "," + notification_arg + "?" + crop_start + "("
    + window_expr + "):(__wisprFlowBarVisible=!1," + clear + ","
    + window_expr + "?.hide()))}"
)
suspend_replacement = (
    suspend_match.group("name") + "=()=>{"
    + suspended_name
    + "||(" + suspended_name + "=!0," + clear + "," + window_expr + "&&!"
    + window_expr + ".isDestroyed()&&" + window_expr + ".hide(),"
    + suspend_match.group("logger")
    + "().info(\"[Status] Crop poll suspended for feature tour\"))}"
)
resume_replacement = (
    resume_match.group("name") + "=()=>{" + suspended_name + "&&(" + suspended_name
    + "=!1," + window_expr + "&&!" + window_expr + ".isDestroyed()?"
    + "(__wisprFlowBarVisible||__wisprFlowNotificationVisible?" + crop_start
    + "(" + window_expr + "):" + window_expr + ".hide()):" + clear + ","
    + resume_match.group("logger")
    + "().info(\"[Status] Crop poll resumed after feature tour\"))}"
)

replacements = [
    (state_match.start(), state_match.end(), state_replacement),
    (start_match.start(), start_match.end(), crop_replacement),
    (hidden.start(), hidden.end(), hidden_replacement),
    (visible.start(), visible.end(), visible_replacement),
    (
        notification_match.start(),
        notification_match.end(),
        notification_replacement,
    ),
    (startup_match.start(), startup_match.end(), startup_replacement),
    (suspend_match.start(), suspend_match.end(), suspend_replacement),
    (resume_match.start(), resume_match.end(), resume_replacement),
]
for begin, end, replacement in sorted(replacements, reverse=True):
    data = data[:begin] + replacement + data[end:]

with io.open(path, "w", encoding="utf-8", errors="surrogateescape") as handle:
    handle.write(data)

print("Patched: status OS surface cropped to visible DOM bounds.")
print("Patched: idle status window remains unmapped.")
print("Patched: notifications no longer enable the full status surface.")
PY
then
	echo 'ERROR: Flow Bar crop patch failed; restoring backup.' >&2
	cp -p "$BACKUP" "$BUNDLE"
	exit 1
fi

required=(
	"$MARKER"
	'webContents.executeJavaScript(__wisprFlowCropProgram,!0)'
	'__wisprLogicalWidth=440'
	'.setBounds({x:Math.round('
	'__wisprFlowBarVisible=!1'
	'__wisprFlowNotificationVisible=!1'
	'Status window lifecycle initialized'
)
for needle in "${required[@]}"; do
	if ! grep -qF "$needle" "$BUNDLE"; then
		echo "ERROR: post-patch verification failed: $needle missing." >&2
		cp -p "$BACKUP" "$BUNDLE"
		exit 1
	fi
done

if grep -qF '.setShape(' "$BUNDLE"; then
	echo 'ERROR: X11 input shapes cannot make a mapped XWayland surface safe.' >&2
	cp -p "$BACKUP" "$BUNDLE"
	exit 1
fi

if command -v node >/dev/null && ! node --check "$BUNDLE"; then
	echo 'ERROR: node --check failed on Flow Bar cropped-surface bundle.' >&2
	cp -p "$BACKUP" "$BUNDLE"
	exit 1
fi

echo "OK: Flow Bar cropped surface installed in $BUNDLE"
