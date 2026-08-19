import QtQuick
import qs.Commons

// One draggable monitor tile on the editor canvas. Position/size are in
// canvas pixels; the parent converts to and from real monitor units using
// pxPerUnit so this component stays unit-agnostic.
Rectangle {
  id: root

  property bool selected: false
  property string label: ""
  property real pxPerUnit: 1

  signal tapped()
  signal moved(real dxUnits, real dyUnits)

  radius: Style.cornerRadius
  color: selected
    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
  border.color: selected ? Color.accent : Color.muted
  border.width: selected ? 2 : 1

  Text {
    anchors.centerIn: parent
    width: parent.width - Style.space(8)
    text: root.label
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    elide: Text.ElideRight
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    cursorShape: Qt.SizeAllCursor
    drag.target: root
    drag.axis: Drag.XAndYAxis

    property real pressStartX: 0
    property real pressStartY: 0

    onPressed: {
      pressStartX = root.x
      pressStartY = root.y
      root.tapped()
    }

    onReleased: {
      var dxUnits = (root.x - pressStartX) / Math.max(1, root.pxPerUnit)
      var dyUnits = (root.y - pressStartY) / Math.max(1, root.pxPerUnit)
      if (dxUnits !== 0 || dyUnits !== 0) root.moved(dxUnits, dyUnits)
    }
  }
}
