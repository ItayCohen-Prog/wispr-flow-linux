import QtQuick

// The Flow Bar capsule: one liquid glass shape that is a pill while
// listening or processing and grows into a card for messages. The item's
// size is the settled geometry (the input mask and tests rely on it); the
// glass forms inside it from a droplet.
Item {
  id: capsule
  property string mode: "hidden"
  property real level: 0
  property var notification: null
  property real availableWidth: 400
  property real availableHeight: 500
  property bool reducedMotion: false
  property bool active: true
  // Frosted material needs a backdrop snapshot; "solid" forces the fallback.
  property bool translucent: true
  property var backdrop: null
  // FlowBar holds this false until the backdrop snapshot has arrived.
  property bool materialReady: true
  readonly property bool wanted: mode !== "hidden" || notification !== null
  readonly property bool expanded: notification !== null
  readonly property bool hovered: hover.hovered
  readonly property bool animating: widthMotion.running || heightMotion.running || appear.running || vanish.running
  readonly property bool processing: mode === "processing" && active && visible && !reducedMotion
  readonly property bool dark: translucent && backdrop && backdrop.luminance >= 0 ? backdrop.luminance < 0.5 : true
  readonly property color ink: dark ? "#ffffff" : "#1c1c1e"
  readonly property color meterColor: mode === "error" ? "#ff9f0a" : ink
  property real phase: 0
  // 0 droplet .. 1 settled shape; may overshoot while the spring settles.
  property real form: 0
  // Overall presence of the glass and its content.
  property real presence: 0
  signal cancel()
  signal stop()
  signal dismiss()
  signal action(var notification, var action)

  readonly property real pillHeight: 46
  readonly property real targetWidth: Math.min(availableWidth, expanded ? 356 : 176)
  readonly property real targetHeight: Math.min(availableHeight, expanded ? details.implicitHeight + 32 + (mode !== "hidden" ? pillHeight + 4 : 0) : pillHeight)
  width: targetWidth
  height: targetHeight
  readonly property real radius: Math.min(expanded ? 26 : 23, height / 2)
  opacity: presence
  visible: wanted || presence > 0
  Behavior on width { enabled: capsule.active && !capsule.reducedMotion; SpringAnimation { id: widthMotion; spring: 4.5; damping: 0.55; mass: 1; epsilon: 0.25 } }
  Behavior on height { enabled: capsule.active && !capsule.reducedMotion; SpringAnimation { id: heightMotion; spring: 4.5; damping: 0.6; mass: 1; epsilon: 0.25 } }

  function sync() {
    if (wanted && materialReady) {
      vanish.stop()
      if (reducedMotion) { appear.stop(); form = 1; presence = 1 } else appear.restart()
    } else if (!wanted) {
      appear.stop()
      if (reducedMotion) { vanish.stop(); form = 0; presence = 0 } else vanish.restart()
    }
  }
  onWantedChanged: sync()
  onMaterialReadyChanged: sync()
  Component.onCompleted: sync()

  // Appear: the droplet swells into the pill with a little bounce.
  ParallelAnimation {
    id: appear
    SpringAnimation { target: capsule; property: "form"; to: 1; spring: 2.6; damping: 0.26; mass: 1; epsilon: 0.002 }
    NumberAnimation { target: capsule; property: "presence"; to: 1; duration: 110; easing.type: Easing.OutCubic }
  }
  // Vanish: it pulls back into a drop and fades.
  ParallelAnimation {
    id: vanish
    NumberAnimation { target: capsule; property: "form"; to: 0; duration: 240; easing.type: Easing.InCubic }
    NumberAnimation { target: capsule; property: "presence"; to: 0; duration: 220; easing.type: Easing.InQuad }
  }

  GlassSurface {
    id: surface
    anchors.fill: parent
    anchors.margins: -28
    backdrop: capsule.translucent ? capsule.backdrop : null
    originX: capsule.x + surface.x
    originY: capsule.y + surface.y
    cornerRadius: capsule.radius
    shapeWidth: capsule.pillHeight + (capsule.width - capsule.pillHeight) * capsule.form
    shapeHeight: capsule.pillHeight + (capsule.height - capsule.pillHeight) * capsule.form
    form: Math.min(capsule.form, 1)
    darkness: capsule.dark ? 1 : 0
    Behavior on darkness { NumberAnimation { duration: capsule.reducedMotion ? 0 : 220 } }
    emphasis: capsule.hovered ? 0.35 : 0
    Behavior on emphasis { NumberAnimation { duration: capsule.reducedMotion ? 0 : 160 } }
    warmth: capsule.mode === "error" ? 1 : 0
    Behavior on warmth { NumberAnimation { duration: capsule.reducedMotion ? 0 : 220 } }
    frost: capsule.expanded ? 1 : 0.85
  }
  HoverHandler { id: hover }

  // Only processing has a clock. Listening is driven by real incoming audio.
  Timer {
    interval: 33
    repeat: true
    running: capsule.processing
    onTriggered: capsule.phase = (capsule.phase + Math.PI * 2 * 33 / 1600) % (Math.PI * 2)
  }

  // Content surfaces once the glass is nearly formed and fades with it.
  readonly property real contentReveal: appear.running ? Math.max(0, Math.min(1, (form - 0.5) / 0.4)) : presence * presence

  Item {
    id: recording
    anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, 176); height: capsule.pillHeight
    visible: capsule.mode !== "hidden"
    opacity: capsule.contentReveal
    scale: 0.92 + 0.08 * capsule.contentReveal
    GlassIconButton {
      anchors.left: parent.left; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter
      kind: "close"; label: "Cancel dictation"; ink: capsule.ink; reduceMotion: capsule.reducedMotion
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
          color: capsule.meterColor
          Behavior on height { enabled: capsule.mode === "listening"; NumberAnimation { duration: capsule.reducedMotion ? 0 : 80; easing.type: Easing.OutCubic } }
        }
      }
    }
    GlassIconButton {
      anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
      kind: "check"; label: "Finish dictation"; ink: capsule.ink; reduceMotion: capsule.reducedMotion
      onClicked: capsule.stop()
    }
  }

  Flickable {
    anchors.left: parent.left; anchors.right: parent.right
    anchors.margins: 18
    y: capsule.mode !== "hidden" ? capsule.pillHeight + 4 + 12 : 16
    height: Math.max(0, capsule.height - y - 16)
    contentWidth: width
    contentHeight: details.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    visible: capsule.expanded
    opacity: capsule.expanded && capsule.width > 240 ? capsule.contentReveal : 0
    Behavior on opacity { NumberAnimation { duration: capsule.reducedMotion ? 0 : 120 } }
    Column {
      id: details
      // Measure text at the destination width, not every spring frame.
      width: Math.max(0, capsule.targetWidth - 36)
      spacing: 10
      Row {
        width: parent.width; spacing: 8
        Text {
          width: parent.width - 40
          anchors.verticalCenter: parent.verticalCenter
          text: capsule.notification ? capsule.notification.title : ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap; color: capsule.ink
          font.family: "Adwaita Sans"; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        GlassIconButton { kind: "close"; label: "Dismiss message"; ink: capsule.ink; reduceMotion: capsule.reducedMotion; onClicked: capsule.dismiss() }
      }
      Text {
        width: parent.width
        text: capsule.notification ? capsule.notification.body : ""
        textFormat: Text.PlainText
        visible: text !== ""
        wrapMode: Text.Wrap; color: capsule.ink; opacity: 0.82
        font.family: "Adwaita Sans"; font.pixelSize: 13; lineHeight: 1.15
      }
      Flow {
        width: parent.width; spacing: 8
        Repeater {
          model: capsule.notification ? capsule.notification.actions : []
          GlassButton {
            required property var modelData
            maximumWidth: details.width
            label: modelData.text; primary: modelData.style === "primary"
            dark: capsule.dark
            reduceMotion: capsule.reducedMotion
            onClicked: capsule.action(capsule.notification, modelData)
          }
        }
      }
    }
  }
}
