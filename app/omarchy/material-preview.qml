import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "plugins/wispr.flowbar" as Flow

Window {
  id: window
  visible: true; width: 1080; height: 700
  title: "Wispr glass material review"
  color: "#20232b"
  property string mode: "listening"
  property bool message: false
  property string callback: ""
  property real audioLevel: 0.65
  property bool moving: false
  Timer { interval: 33; repeat: true; running: window.moving && window.mode === "listening"; onTriggered: window.audioLevel = 0.2 + 0.75 * Math.abs(Math.sin(Date.now()/180)) }
  Text { x: 28; y: 22; text: "WISPR FLOW  /  MATERIAL REVIEW"; color: "#b1b6c3"; font.pixelSize: 12; font.letterSpacing: 2 }
  Row {
    x: 24; y: 68; spacing: 12
    Repeater {
      model: ["Frosted grey", "Colour", "Dark content"]
      delegate: Item {
        id: sample
        required property int index
        required property string modelData
        width: 336; height: 470
        Item {
          id: background
          anchors.fill: parent
          clip: true
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop { position: 0; color: sample.index === 0 ? "#b1b6c3" : sample.index === 1 ? "#bd68ec" : "#171920" }
              GradientStop { position: 1; color: sample.index === 0 ? "#646d81" : sample.index === 1 ? "#6222aa" : "#303540" }
            }
          }
          Rectangle { visible: sample.index === 1; x: -40; y: 135; width: 260; height: 260; radius: 130; color: "#ffc949" }
          Rectangle { visible: sample.index === 1; x: 200; y: 75; width: 170; height: 170; radius: 85; color: "#6637ff" }
          Rectangle { visible: sample.index === 1; x: 200; y: 350; width: 240; height: 240; radius: 120; color: "#ef9030" }
          Column {
            visible: sample.index === 2
            x: 25; y: 120; spacing: 16
            Repeater { model: 12; Text { text: "Your words, wherever you work."; color: "#8c92a1"; font.pixelSize: 15 } }
          }
          Text { x: 22; y: 22; text: sample.modelData; color: "#ffffff"; font.pixelSize: 22; font.weight: Font.DemiBold }
          Text { x: 22; y: 57; text: "Actual QML • preview backdrop blur"; color: "#e0e2e9"; font.pixelSize: 12 }
        }
        // Preview only: Qt can sample this window's own background. Production
        // obtains the desktop blur from Hyprland, never from a screenshot loop.
        ShaderEffectSource {
          id: capture
          sourceItem: background
          sourceRect: Qt.rect(capsule.x, capsule.y, capsule.width, capsule.height)
          textureSize: Qt.size(Math.max(1,capsule.width),Math.max(1,capsule.height))
          visible: false
        }
        Rectangle { id: mask; width: capsule.width; height: capsule.height; radius: capsule.radius; color: "white"; layer.enabled: true; visible: false }
        MultiEffect {
          x: capsule.x; y: capsule.y; width: capsule.width; height: capsule.height
          source: capture; maskEnabled: true; maskSource: mask
          blurEnabled: true; blur: 1; blurMax: 32; autoPaddingEnabled: false
          opacity: capsule.opacity
        }
        Flow.GlassCapsule {
          id: capsule
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom; anchors.bottomMargin: 42
          mode: window.mode; level: window.audioLevel; availableWidth: 292
          notification: window.message ? {title:"Microphone unavailable", body:"Check your input device, then try again.", actions:[{text:"Try again",style:"primary",callback:"retry"},{text:"Dismiss",callback:"dismiss"}]} : null
          onCancel: { window.callback = "Cancel"; window.mode = "hidden" }
          onStop: { window.callback = "Finish"; window.mode = "processing" }
          onDismiss: { window.callback = "Dismiss"; window.message = false }
          onAction: (n,a) => { window.callback = a.callback; window.message = false }
        }
      }
    }
  }
  Row {
    x: 28; y: 570; spacing: 14
    Repeater {
      model: ["Listen", "Process", "Error", "Hide", "Animate", "Capture"]
      Flow.GlassButton {
        required property string modelData
        label: modelData
        onClicked: {
          if (modelData === "Listen") { window.mode = "listening"; window.message = false }
          if (modelData === "Process") { window.mode = "processing"; window.message = false }
          if (modelData === "Error") { window.mode = "hidden"; window.message = true }
          if (modelData === "Hide") { window.mode = "hidden"; window.message = false }
          if (modelData === "Animate") window.moving = !window.moving
          if (modelData === "Capture") window.contentItem.grabToImage(function(result) { result.saveToFile(Qt.resolvedUrl("material.png").toString().replace("file://", "")) })
        }
      }
    }
  }
  Text { x: 28; y: 629; color: "#bbc2d0"; text: "Callback: " + window.callback; font.pixelSize: 13 }
}
