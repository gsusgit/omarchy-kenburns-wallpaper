import QtQuick
import QtQuick.Shapes

// Lucide "aperture" (24×24 viewBox). Stroke follows `color` so the bar
// Light/Dark theme tints it the same way as the rest of the icons.
Item {
  id: root
  property color color: "white"

  readonly property real unit: Math.min(width, height) / 24

  Shape {
    anchors.centerIn: parent
    width: 24 * root.unit
    height: 24 * root.unit
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      PathAngleArc {
        centerX: 12 * root.unit
        centerY: 12 * root.unit
        radiusX: 10 * root.unit
        radiusY: 10 * root.unit
        startAngle: 0
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 14.31 * root.unit
      startY: 8 * root.unit
      PathLine { x: 20.05 * root.unit; y: 17.94 * root.unit }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 9.69 * root.unit
      startY: 8 * root.unit
      PathLine { x: 21.17 * root.unit; y: 8 * root.unit }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 7.38 * root.unit
      startY: 12 * root.unit
      PathLine { x: 13.12 * root.unit; y: 2.06 * root.unit }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 9.69 * root.unit
      startY: 16 * root.unit
      PathLine { x: 3.95 * root.unit; y: 6.06 * root.unit }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 14.31 * root.unit
      startY: 16 * root.unit
      PathLine { x: 2.83 * root.unit; y: 16 * root.unit }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: 2 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 16.62 * root.unit
      startY: 12 * root.unit
      PathLine { x: 10.88 * root.unit; y: 21.94 * root.unit }
    }
  }
}
