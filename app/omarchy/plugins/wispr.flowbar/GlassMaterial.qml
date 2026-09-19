import QtQuick

Item {
  id: material
  property real radius: 24
  property color tint: "#887c8495"
  property real emphasis: 0
  property bool shadow: true
  readonly property bool shaderAvailable: GraphicsInfo.api !== GraphicsInfo.Software

  ShaderEffect {
    anchors.fill: parent
    anchors.margins: material.shadow ? -16 : 0
    visible: material.shaderAvailable
    property vector2d size: Qt.vector2d(width, height)
    property real cornerRadius: material.radius
    property real padding: material.shadow ? 16 : 0
    property color tint: material.tint
    property real emphasis: material.emphasis
    fragmentShader: "shaders/glass.frag.qsb"
  }
  // Software rendering remains usable on systems without a shader backend.
  Rectangle {
    anchors.fill: parent
    visible: !material.shaderAvailable
    radius: material.radius
    color: material.tint
    border.width: 1
    border.color: "#b8e8edf4"
    gradient: Gradient {
      GradientStop { position: 0; color: "#bd9099aa" }
      GradientStop { position: 0.2; color: "#a5687285" }
      GradientStop { position: 1; color: "#ac7d8797" }
    }
  }
}
