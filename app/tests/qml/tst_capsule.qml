import QtQuick
import QtTest
import "../../omarchy/plugins/wispr.flowbar" as FlowBar

TestCase {
  name: "GlassCapsule"
  when: windowShown
  visible: true
  width: 480; height: 480
  FlowBar.GlassCapsule { id: capsule; anchors.centerIn: parent }
  SignalSpy { id: cancelSpy; target: capsule; signalName: "cancel" }
  SignalSpy { id: stopSpy; target: capsule; signalName: "stop" }
  function init() { capsule.reducedMotion = true; capsule.mode = "hidden"; capsule.notification = null; capsule.availableWidth = 400; capsule.availableHeight = 500; capsule.active = true; capsule.level = 0 }
  function test_idle_has_no_motion() {
    compare(capsule.wanted, false); compare(capsule.processing, false)
    tryCompare(capsule, "visible", false)
  }
  function test_processing_moves_only_while_visible() {
    capsule.reducedMotion = false; capsule.mode = "processing"
    tryCompare(capsule, "processing", true)
    wait(200); var oldPhase = capsule.phase; wait(100)
    verify(capsule.phase !== oldPhase)
    var bar = findChild(capsule, "levelBar0"); var oldHeight = bar.height; wait(150)
    verify(bar.height !== oldHeight)
    capsule.mode = "hidden"; wait(300); oldPhase = capsule.phase; wait(100)
    compare(capsule.phase, oldPhase)
  }
  function test_long_message_is_bounded() {
    capsule.notification = {title:"A long message",body:"Check your input device. ".repeat(100),actions:[]}
    capsule.availableHeight = 240
    tryCompare(capsule, "height", 240)
  }
  function test_inactive_monitor_does_not_animate_processing() {
    capsule.reducedMotion = false; capsule.mode = "processing"; capsule.active = false
    compare(capsule.processing, false)
  }
  function test_recording_buttons() {
    capsule.mode = "listening"; wait(10)
    compare(capsule.width, 176); compare(capsule.height, 46)
    mouseClick(capsule, 23, 23); compare(cancelSpy.count, 1)
    mouseClick(capsule, 153, 23); compare(stopSpy.count, 1)
  }
  function test_notification_without_recording() {
    capsule.notification = {title:"Microphone unavailable",body:"Choose another input device.",actions:[]}
    compare(capsule.wanted, true); verify(capsule.height > 46)
    compare(capsule.width, 356)
    capsule.availableWidth = 280; compare(capsule.width, 280)
  }
  function test_interrupted_animation_settles_and_stops() {
    capsule.reducedMotion = false
    capsule.mode = "listening"; wait(30)
    capsule.notification = {title:"Test",body:"An interrupted transition",actions:[]}; wait(30)
    capsule.mode = "hidden"; capsule.notification = null
    tryCompare(capsule, "opacity", 0, 1500)
    tryCompare(capsule, "animating", false, 2500)
    compare(capsule.processing, false)
  }
}
