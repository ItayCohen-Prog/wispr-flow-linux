import QtQuick

// The liquid glass material for one shape. It draws a rounded rectangle of
// `shapeWidth` x `shapeHeight` centred in the item; the rest of the item is
// transparent except for the drop shadow. Without a ready backdrop (tests,
// software rendering) it falls back to a plain frosted tint.
Item {
  id: surface
  property var backdrop: null
  property real cornerRadius: 23
  property real shapeWidth: width
  property real shapeHeight: height
  // 0 forming .. 1 settled: the rim lens is thicker while forming.
  property real form: 1
  property real emphasis: 0
  // 0 light glass .. 1 dark glass
  property real darkness: 1
  property real frost: 1
  property real warmth: 0
  // Position of this item's top-left corner inside the backdrop textures.
  property real originX: x
  property real originY: y
  readonly property bool live: backdrop !== null && backdrop.ready && GraphicsInfo.api !== GraphicsInfo.Software

  ShaderEffect {
    anchors.fill: parent
    visible: surface.live
    property var sharpTex: surface.backdrop ? surface.backdrop.sharp : null
    property var frostTex: surface.backdrop ? surface.backdrop.frosted : null
    property vector2d size: Qt.vector2d(width, height)
    property vector2d shapeHalf: Qt.vector2d(surface.shapeWidth / 2, surface.shapeHeight / 2)
    property real cornerRadius: surface.cornerRadius
    property real form: surface.form
    property real emphasis: surface.emphasis
    property real darkness: surface.darkness
    property real frost: surface.frost
    property real warmth: surface.warmth
    property vector2d texOrigin: Qt.vector2d(surface.originX, surface.originY)
    property vector2d texSize: surface.backdrop ? Qt.vector2d(surface.backdrop.width, surface.backdrop.height) : Qt.vector2d(1, 1)
    fragmentShader: "shaders/lens.frag.qsb"
  }
  Rectangle {
    visible: !surface.live
    anchors.centerIn: parent
    width: surface.shapeWidth; height: surface.shapeHeight
    radius: Math.min(surface.cornerRadius, height / 2)
    color: surface.darkness > 0.5 ? "#c8373737" : "#c8f4f2ee"
    border.width: 1
    border.color: surface.darkness > 0.5 ? "#50ffffff" : "#40000000"
  }
}
