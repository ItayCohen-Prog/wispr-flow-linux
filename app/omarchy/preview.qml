import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/wispr.flowbar" as FlowBar

// Standalone native preview: quickshell -p app/omarchy/preview.qml
ShellRoot {
  FlowBar.FlowBar { }
  FloatingWindow {
    id: demo
    title: "Wispr Flow glass preview"
    implicitWidth: 960; implicitHeight: 640
    color: "#17262f"
    readonly property string scene: Quickshell.env("WISPR_FLOWBAR_PREVIEW_SCENE") || "teal"
    property string response: "Ready. Controls send the same messages as Wispr."
    property string socketPath: Quickshell.env("WISPR_FLOWBAR_SOCKET") || (Quickshell.env("XDG_RUNTIME_DIR") + "/wispr-flow/flowbar.sock")
    function send(t, p) { client.write(JSON.stringify({t:t,p:p}) + "\n"); client.flush() }
    Socket {
      id: client
      path: demo.socketPath
      connected: false
      onError: { connected = false; retry.restart() }
      parser: SplitParser { onRead: data => { demo.response = data; demo.send("status:dictationStatus", "idle") } }
    }
    Timer { id: retry; interval: 500; running: true; onTriggered: client.connected = true }
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: demo.scene === "grey" ? "#b0b7c6" : demo.scene === "colour" ? "#d084eb" : "#183b42" }
        GradientStop { position: 0.5; color: demo.scene === "grey" ? "#858d9e" : demo.scene === "colour" ? "#b156db" : "#637a7c" }
        GradientStop { position: 1; color: demo.scene === "grey" ? "#626e83" : demo.scene === "colour" ? "#5f27b6" : "#364451" }
      }
    }
    Rectangle { visible: demo.scene === "colour"; x: demo.width / 2 - 240; y: demo.height - 180; width: 280; height: 280; radius: 140; color: "#ffd351" }
    Rectangle { visible: demo.scene === "colour"; x: demo.width / 2 + 80; y: demo.height - 70; width: 260; height: 260; radius: 130; color: "#ef952b" }
    Row {
      visible: Quickshell.env("WISPR_FLOWBAR_TEST_PATTERN") === "1"
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      height: 200
      Repeater {
        model: 32
        Rectangle { required property int index; width: 16; height: 200; color: index % 2 ? "#7faba0" : "#254a64" }
      }
    }
    Rectangle {
      anchors.left: parent.left; anchors.bottom: parent.bottom
      anchors.leftMargin: 36; anchors.bottomMargin: 30
      width: 230; height: 46; radius: 12; color: "#d7e5e6"
      TextEdit {
        anchors.fill: parent; anchors.margins: 12
        text: "Click-through target"; font.pixelSize: 14; color: "#203c42"
      }
    }
    Column {
      anchors.fill: parent; anchors.margins: 36; spacing: 22
      Text { text: "Wispr Flow"; color: "white"; font.pixelSize: 32; font.weight: Font.DemiBold }
      Text { text: "A quiet place to think."; color: "#d1e2e8"; font.pixelSize: 18 }
      Flow {
        width: parent.width; spacing: 12
        Repeater {
          model: ["Listen", "Process", "Error", "Long message", "Hide"]
          FlowBar.GlassButton {
            required property string modelData
            label: modelData
            onClicked: {
              demo.response = "Preview: " + modelData
              demo.send("notification:clear", null)
              if (modelData === "Error" || modelData === "Long message") {
                demo.send("status:dictationStatus", "idle")
                demo.send("notification:show", {type:"AudioQualityIssue",title:"We couldn't hear you clearly",body:modelData === "Long message" ? "Your microphone level is too low. Check the input device and move closer to the microphone, then try dictating again. This message stays readable as the capsule expands." : "Check your microphone and try again.",timeout:30000,callbackOperationId:"preview",actions:[{text:"Try again",callback:"Retry",style:"primary"},{text:"Dismiss",callback:"Dismiss"}]})
              } else demo.send("status:dictationStatus", modelData === "Listen" ? "listening" : modelData === "Process" ? "processing" : "idle")
            }
          }
        }
      }
      Text { text: "Microphone level"; color: "white"; font.pixelSize: 14 }
      Row {
        spacing: 10
        Repeater {
          model: [0, 0.2, 0.5, 0.8, 1]
          FlowBar.GlassButton { required property real modelData; label: String(modelData); onClicked: demo.send("status:audioLevel", modelData) }
        }
      }
      Rectangle {
        width: parent.width; height: 160; radius: 14; color: "#eaf0ef"
        TextEdit { anchors.fill: parent; anchors.margins: 18; text: "Click here to check that the overlay leaves keyboard focus and the surrounding desktop alone."; wrapMode: TextEdit.Wrap; font.pixelSize: 18; color: "#203c42" }
      }
      Text { width: parent.width; text: demo.response; wrapMode: Text.Wrap; color: "#f2f7f8"; font.pixelSize: 12 }
    }
  }
}
