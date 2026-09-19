import QtQuick

Rectangle {
  id: button
  property string label: ""
  property string glyph: ""
  property real maximumWidth: 400
  property bool primary: false
  property bool reduceMotion: false
  readonly property bool hovered: pointer.containsMouse
  signal clicked()
  implicitWidth: glyph !== "" ? 30 : Math.min(maximumWidth, Math.max(72, caption.implicitWidth + 24))
  implicitHeight: 30
  radius: 15
  color: primary ? (pointer.pressed ? "#dce8ec" : "#f0f4f5") :
         (pointer.pressed ? "#40ffffff" : pointer.containsMouse ? "#26ffffff" : "#12ffffff")
  border.width: primary ? 0 : 1
  border.color: "#20ffffff"
  scale: pointer.pressed ? 0.94 : 1
  Behavior on scale { NumberAnimation { duration: button.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }
  Behavior on color { ColorAnimation { duration: button.reduceMotion ? 0 : 100 } }
  Text {
    id: caption
    anchors.centerIn: parent
    width: Math.max(0, parent.width - 12)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: button.glyph || button.label
    textFormat: Text.PlainText
    color: button.primary ? "#172329" : "#f2f6f7"
    font.family: "sans-serif"
    font.pixelSize: button.glyph !== "" ? 16 : 12
    font.weight: Font.Medium
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
