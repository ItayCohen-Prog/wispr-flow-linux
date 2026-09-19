import QtQuick

Item {
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
  GlassMaterial {
    anchors.fill: parent
    radius: 15
    shadow: false
    tint: button.primary ? "#388f9daf" : "#107e8ca2"
    emphasis: pointer.pressed ? 1 : pointer.containsMouse ? 0.6 : button.primary ? 0.25 : 0
    Behavior on emphasis { NumberAnimation { duration: button.reduceMotion ? 0 : 120 } }
  }
  scale: pointer.pressed ? 0.94 : 1
  Behavior on scale { NumberAnimation { duration: button.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }
  Text {
    id: caption
    anchors.centerIn: parent
    width: Math.max(0, parent.width - 12)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: button.glyph || button.label
    textFormat: Text.PlainText
    color: "#ffffff"
    style: Text.Raised
    styleColor: "#60303a50"
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
