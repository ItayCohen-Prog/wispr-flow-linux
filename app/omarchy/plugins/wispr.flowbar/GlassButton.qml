import QtQuick

// A text action inside the glass card. Apple keeps glass off glass, so
// these are plain capsules: the primary one is filled with the ink colour,
// the others are a faint wash of it.
Item {
  id: button
  property string label: ""
  property real maximumWidth: 400
  property bool primary: false
  property bool dark: true
  property bool reduceMotion: false
  readonly property color ink: dark ? "#ffffff" : "#1c1c1e"
  readonly property bool hovered: pointer.containsMouse
  signal clicked()
  implicitWidth: Math.min(maximumWidth, Math.max(72, caption.implicitWidth + 28))
  implicitHeight: 30
  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: button.ink
    opacity: button.primary ? (pointer.pressed ? 0.78 : pointer.containsMouse ? 0.92 : 1)
                            : (pointer.pressed ? 0.26 : pointer.containsMouse ? 0.19 : 0.13)
    Behavior on opacity { NumberAnimation { duration: button.reduceMotion ? 0 : 120 } }
  }
  scale: pointer.pressed ? 0.96 : 1
  Behavior on scale { NumberAnimation { duration: button.reduceMotion ? 0 : 110; easing.type: Easing.OutCubic } }
  Text {
    id: caption
    anchors.centerIn: parent
    width: Math.max(0, parent.width - 16)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: button.label
    textFormat: Text.PlainText
    color: button.primary ? (button.dark ? "#1c1c1e" : "#ffffff") : button.ink
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    font.weight: Font.DemiBold
  }
  Accessible.role: Accessible.Button
  Accessible.name: label
  Accessible.onPressAction: clicked()
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
