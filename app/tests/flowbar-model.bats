#!/usr/bin/env bats
#
# flowbar-model.bats -- the native Flow Bar reducer (omarchy/plugins/
# wispr.flowbar/FlowBarModel.js) is shared by the Quickshell plugin and this
# node-driven test; keep it free of QML/Node-only APIs.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../omarchy/plugins/wispr.flowbar"

setup() {
	command -v node >/dev/null || skip 'node not installed'
}

run_model() {
	run node -e "$1" "$PLUGIN_DIR/FlowBarModel.js"
}

@test "flowbar-model: dictation lifecycle drives mode and level" {
	run_model '
const M=require(process.argv[1]);let s=M.initial();
if(M.visible(s))process.exit(10);
s=M.reduce(s,{t:"status:dictationStatus",p:"listening"});
if(s.mode!=="listening"||!M.visible(s))process.exit(1);
s=M.reduce(s,{t:"status:audioLevel",p:1});
if(!(s.level>0.5&&s.level<=1))process.exit(2);
s=M.reduce(s,{t:"status:dictationStatus",p:"processing"});
if(s.mode!=="processing"||s.level!==0)process.exit(3);
s=M.reduce(s,{t:"status:dictationStatus",p:"idle"});
if(s.mode!=="hidden"||M.visible(s))process.exit(4);
'
	[[ "$status" -eq 0 ]]
}

@test "flowbar-model: indicator states map to modes" {
	run_model '
const M=require(process.argv[1]);let s=M.initial();
s=M.reduce(s,{t:"status:setIndicatorState",p:{state:"polish_processing"}});
if(s.mode!=="processing"||s.indicator!=="polish_processing")process.exit(1);
s=M.reduce(s,{t:"status:setIndicatorState",p:{state:"polish_failed"}});
if(s.mode!=="error")process.exit(2);
s=M.reduce(s,{t:"status:setIndicatorState",p:{state:"resting"}});
if(s.mode!=="hidden")process.exit(3);
s=M.reduce(s,{t:"status:dictationStatus",p:"listening"});
s=M.reduce(s,{t:"status:setIndicatorState",p:{state:"hidden"}});
if(s.mode!=="listening")process.exit(4);
'
	[[ "$status" -eq 0 ]]
}

@test "flowbar-model: notifications show and clear independently" {
	run_model '
const M=require(process.argv[1]);let s=M.initial();
s=M.reduce(s,{t:"notification:show",p:{title:"T",body:"B",timeout:10}});
if(!M.visible(s)||s.notification.title!=="T"||s.notification.timeout!==10)process.exit(1);
if(s.mode!=="hidden")process.exit(2);
s=M.reduce(s,{t:"notification:clear",p:null});
if(M.visible(s)||s.notification!==null)process.exit(3);
s=M.reduce(s,{t:"bogus"});
s=M.reduce(s,null);
if(M.visible(s))process.exit(4);
'
	[[ "$status" -eq 0 ]]
}

@test "flowbar-model: i18n keys resolve through the string table with params" {
	run_model '
const M=require(process.argv[1]);
const strings={new_mic_detected_title:"{{name}} detected",new_mic_detected_body:"Would you like to use this mic for Flow?",new_mic_detected_switch:"Switch"};
let s=M.initial();
s=M.reduce(s,{t:"hello",p:{resourcesPath:"/opt/x/resources"}});
if(s.resourcesPath!=="/opt/x/resources")process.exit(1);
s=M.reduce(s,{t:"notification:show",p:{type:"NewMicDetected",title:{key:"new_mic_detected_title",params:{name:"Jabra"}},body:{key:"new_mic_detected_body"},actions:[{text:{key:"new_mic_detected_switch"},callback:"SwitchToNewMic",style:"primary"},{text:{key:"unknown_key_here"},callback:"DismissNewMic"}],callbackOperationId:"op1",timeout:5000}},strings);
const n=s.notification;
if(n.title!=="Jabra detected")process.exit(2);
if(n.body!=="Would you like to use this mic for Flow?")process.exit(3);
if(n.actions.length!==2||n.actions[0].text!=="Switch"||n.actions[0].style!=="primary")process.exit(4);
if(n.actions[1].text!=="Unknown key here")process.exit(5);
const cb=M.callbackPayload(n,n.actions[0]);
if(cb.callback!=="SwitchToNewMic"||cb.type!=="NewMicDetected"||cb.callbackOperationId!=="op1")process.exit(6);
'
	[[ "$status" -eq 0 ]]
}

@test "flowbar-model: custom-variant notifications get readable text" {
	run_model '
const M=require(process.argv[1]);
let s=M.reduce(M.initial(),{t:"notification:show",p:{type:"AudioQualityIssue",variant:"custom",title:"custom",window:"status",timeout:30000}},{audio_quality_title:"We could not hear you well"});
if(s.notification.title!=="We could not hear you well")process.exit(1);
if(s.notification.body==="")process.exit(2);
s=M.reduce(M.initial(),{t:"notification:show",p:{type:"AudioQualityIssue",title:"custom"}});
if(s.notification.title!=="Poor audio quality")process.exit(3);
s=M.reduce(M.initial(),{t:"notification:show",p:{type:"SomethingNewHere",title:"custom",body:"custom"}});
if(s.notification.title!=="Something new here")process.exit(4);
if(M.humanize("wrong_language_setting_title")!=="Wrong language setting title")process.exit(5);
'
	[[ "$status" -eq 0 ]]
}
