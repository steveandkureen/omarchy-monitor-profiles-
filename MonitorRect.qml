import QtQuick
import qs.Commons

// One draggable monitor tile on the editor canvas. Position/size are in
// canvas pixels; the parent converts to and from real monitor units using
// pxPerUnit so this component stays unit-agnostic.
//
// Dragging is tracked manually (mouse deltas accumulated into root.x/y)
// rather than via MouseArea.drag.target: target's x/y here are QML bindings
// owned by the parent's Repeater delegate, and drag.target's job is to
// override exactly that kind of binding by writing to it directly — which
// this environment's Quickshell/Qt build was not reliably doing (tiles
// wouldn't move at all). Manual tracking sidesteps whatever that was.
Rectangle {
  id: root

  property bool selected: false
  property string label: ""
  property real pxPerUnit: 1
  // Other tiles' current canvas-pixel rects ({x,y,width,height}), for drag
  // collision checks. Provided by the parent; excludes this tile.
  property var obstacles: []

  signal tapped()
  signal moved(real dxUnits, real dyUnits)

  radius: Style.cornerRadius
  color: selected
    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
  border.color: dragArea.dragging ? Color.accent : (selected ? Color.accent : Color.muted)
  border.width: selected || dragArea.dragging ? 2 : 1

  function rectsOverlap(a, b) {
    return a.x < b.x + b.width && a.x + a.width > b.x &&
           a.y < b.y + b.height && a.y + a.height > b.y
  }

  function collidesAt(x, y) {
    var candidate = { x: x, y: y, width: root.width, height: root.height }
    for (var i = 0; i < root.obstacles.length; i++) {
      if (rectsOverlap(candidate, root.obstacles[i])) return true
    }
    return false
  }

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
    preventStealing: true

    property bool dragging: false
    // Local mouse position at press, in this MouseArea's own coordinate
    // frame — deliberately never updated after that. Because the MouseArea
    // moves with root, `root.x + (mouse.x - pressLocalX)` gives the correct
    // total offset from the press point on every event regardless of how
    // root.x got to its current value — including when a prior event's
    // candidate was rejected for colliding and left root.x unchanged. (The
    // algebra: candidate = root.x + mouse.x - pressLocalX, and mouse.x
    // itself is `absoluteCursorX - root.x` at read time, so root.x cancels
    // out — candidate only ever depends on how far the cursor has moved
    // since press.) Re-deriving pressLocalX from the running position, or
    // resetting it after each accepted move, does not have this property.
    property real pressLocalX: 0
    property real pressLocalY: 0
    property real startTileX: 0
    property real startTileY: 0

    onPressed: function(mouse) {
      pressLocalX = mouse.x
      pressLocalY = mouse.y
      startTileX = root.x
      startTileY = root.y
      dragging = true
      root.tapped()
    }

    onPositionChanged: function(mouse) {
      if (!dragging) return
      var candidateX = root.x + (mouse.x - pressLocalX)
      var candidateY = root.y + (mouse.y - pressLocalY)
      if (!root.collidesAt(candidateX, candidateY)) {
        root.x = candidateX
        root.y = candidateY
      }
      // A colliding candidate is simply not applied; root.x/y (and so the
      // next event's baseline) stays put until the cursor backs out of it.
    }

    onReleased: {
      dragging = false
      var dxUnits = (root.x - startTileX) / Math.max(1, root.pxPerUnit)
      var dyUnits = (root.y - startTileY) / Math.max(1, root.pxPerUnit)
      if (dxUnits !== 0 || dyUnits !== 0) root.moved(dxUnits, dyUnits)
    }
  }
}
