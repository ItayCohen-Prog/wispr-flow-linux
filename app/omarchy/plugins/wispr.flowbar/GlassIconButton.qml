import QtQuick

// An icon sitting directly on the glass. Hover lifts a soft disc of light
// under it; pressing squashes it slightly. No permanent chrome.
Item {
  id: button
  property string kind: "close"
  property string label: ""
  property color ink: "#ffffff"
  property bool reduceMotion: false
  readonly property bool hovered: pointer.containsMouse
  signal clicked()
  implicitWidth: 32; implicitHeight: 32
  Rectangle {
    anchors.centerIn: parent
    width: 26; height: 26; radius: 13
    color: button.ink
    opacity: pointer.pressed ? 0.22 : pointer.containsMouse ? 0.14 : 0
    Behavior on opacity { NumberAnimation { duration: button.reduceMotion ? 0 : 140; easing.type: Easing.OutCubic } }
  }
  GlassIcon {
    anchors.centerIn: parent
    kind: button.kind
    color: button.ink
    scale: pointer.pressed ? 0.86 : 1
    Behavior on scale { NumberAnimation { duration: button.reduceMotion ? 0 : 110; easing.type: Easing.OutCubic } }
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
