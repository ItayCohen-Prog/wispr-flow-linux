import QtQuick

Item {
  id: capsule
  property string mode: "hidden"
  property real level: 0
  property var notification: null
  property real availableWidth: 400
  property real availableHeight: 500
  property bool reducedMotion: false
  property bool active: true
  // Frosted material needs the scoped Hyprland layer blur rule.
  property bool translucent: true
  readonly property bool wanted: mode !== "hidden" || notification !== null
  readonly property bool expanded: notification !== null
  readonly property bool hovered: hover.hovered
  readonly property bool animating: widthMotion.running || heightMotion.running || opacityMotion.running
  readonly property bool processing: mode === "processing" && active && visible && !reducedMotion
  property real phase: 0
  signal cancel()
  signal stop()
  signal dismiss()
  signal action(var notification, var action)

  width: wanted ? Math.min(availableWidth, expanded ? 356 : 176) : 110
  height: wanted ? Math.min(availableHeight, expanded ? details.implicitHeight + 28 + (mode !== "hidden" ? 46 : 0) : 46) : 16
  readonly property real radius: Math.min(24, height / 2)
  opacity: wanted ? 1 : 0
  visible: wanted || opacity > 0
  Behavior on width { enabled: capsule.active && !capsule.reducedMotion; SpringAnimation { id: widthMotion; spring: capsule.reducedMotion ? 0 : 4.5; damping: 0.82; mass: 1; epsilon: 0.25 } }
  Behavior on height { enabled: capsule.active && !capsule.reducedMotion; SpringAnimation { id: heightMotion; spring: capsule.reducedMotion ? 0 : 4.5; damping: 0.86; mass: 1; epsilon: 0.25 } }
  Behavior on opacity { NumberAnimation { id: opacityMotion; duration: capsule.reducedMotion ? 0 : 160; easing.type: Easing.OutCubic } }

  GlassMaterial {
    anchors.fill: parent
    radius: capsule.radius
    tint: capsule.translucent ? "#887c8495" : "#f2586374"
  }
  HoverHandler { id: hover }

  // Only processing has a clock. Listening is driven by real incoming audio.
  Timer {
    interval: 33
    repeat: true
    running: capsule.processing
    onTriggered: capsule.phase = (capsule.phase + Math.PI * 2 * 33 / 1600) % (Math.PI * 2)
  }

  Item {
    id: recording
    anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, 176); height: 46
    visible: capsule.mode !== "hidden"
    opacity: capsule.wanted ? 1 : 0
    GlassButton {
      anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
      label: "Cancel dictation"; glyph: "×"; reduceMotion: capsule.reducedMotion
      onClicked: capsule.cancel()
    }
    Row {
      anchors.centerIn: parent; spacing: 3
      Repeater {
        model: 11
        Rectangle {
          required property int index
          objectName: "levelBar" + index
          readonly property real weight: 0.45 + 0.55 * Math.cos((index - 5) * 0.25)
          width: 3; radius: 1.5
          height: capsule.mode === "listening" ? 4 + 21 * capsule.level * weight :
                  capsule.processing ? 5 + 10 * (0.5 + 0.5 * Math.sin(capsule.phase - index * 0.42)) : 5
          anchors.verticalCenter: parent.verticalCenter
          color: capsule.mode === "error" ? "#efc49f" : "#e9f6fa"
          Behavior on height { enabled: capsule.mode === "listening"; NumberAnimation { duration: capsule.reducedMotion ? 0 : 80; easing.type: Easing.OutCubic } }
        }
      }
    }
    GlassButton {
      anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
      label: "Finish dictation"; glyph: "✓"; primary: true; reduceMotion: capsule.reducedMotion
      onClicked: capsule.stop()
    }
  }

  Flickable {
    anchors.left: parent.left; anchors.right: parent.right
    anchors.margins: 18
    y: capsule.mode !== "hidden" ? 54 : 14
    height: Math.max(0, capsule.height - y - 14)
    contentWidth: width
    contentHeight: details.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    visible: capsule.expanded
    opacity: capsule.expanded && capsule.width > 240 ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: capsule.reducedMotion ? 0 : 120 } }
    Column {
      id: details
      width: parent.width
      spacing: 10
      Row {
        width: parent.width; spacing: 8
        Text {
          width: parent.width - 38
          text: capsule.notification ? capsule.notification.title : ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap; color: "#f6f8f9"
          font.family: "sans-serif"; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        GlassButton { label: "Dismiss message"; glyph: "×"; reduceMotion: capsule.reducedMotion; onClicked: capsule.dismiss() }
      }
      Text {
        width: parent.width
        text: capsule.notification ? capsule.notification.body : ""
        textFormat: Text.PlainText
        visible: text !== ""
        wrapMode: Text.Wrap; color: "#d8e2e7"; font.pixelSize: 13; lineHeight: 1.15
      }
      Flow {
        width: parent.width; spacing: 8
        Repeater {
          model: capsule.notification ? capsule.notification.actions : []
          GlassButton {
            required property var modelData
            maximumWidth: details.width
            label: modelData.text; primary: modelData.style === "primary"
            reduceMotion: capsule.reducedMotion
            onClicked: capsule.action(capsule.notification, modelData)
          }
        }
      }
    }
  }
}
