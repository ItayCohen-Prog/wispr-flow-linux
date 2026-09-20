import QtQuick
import QtQuick.Shapes

// Bare glyphs on the glass: a close cross or a check mark drawn as strokes
// with round caps, sized to the SF Symbols weight Apple uses on glass.
Item {
  id: icon
  property string kind: "close"
  property color color: "#ffffff"
  property real strokeWidth: 2.2
  implicitWidth: 12; implicitHeight: 12
  Shape {
    id: shape
    anchors.fill: parent
    // The curve renderer (Qt 6.6+) antialiases the strokes; older Qt
    // draws them with the geometry renderer.
    Component.onCompleted: if (shape.preferredRendererType !== undefined) shape.preferredRendererType = Shape.CurveRenderer
    ShapePath {
      strokeColor: icon.color
      strokeWidth: icon.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: icon.kind === "check" ? 1 : 1.5
      startY: icon.kind === "check" ? 6.5 : 1.5
      PathLine { x: icon.kind === "check" ? 4.6 : 10.5; y: icon.kind === "check" ? 10 : 10.5 }
      PathLine { x: icon.kind === "check" ? 11 : 10.5; y: icon.kind === "check" ? 2 : 10.5 }
    }
    ShapePath {
      strokeColor: icon.kind === "close" ? icon.color : "transparent"
      strokeWidth: icon.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: 10.5; startY: 1.5
      PathLine { x: 1.5; y: 10.5 }
    }
  }
}
