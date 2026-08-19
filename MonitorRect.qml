import QtQuick
import qs.Commons

// One monitor tile on the editor canvas. Position/size are in canvas
// pixels; the parent converts to and from real monitor units using
// pxPerUnit so this component stays unit-agnostic.
//
// The primary tile (isPrimary) stays at unit (0,0) — every other tile's
// position is stored relative to it — but it still drags like any other
// tile; dragging it pans the canvas (see panned()/onPanned in EditorView)
// rather than moving it in the layout, so it's still reachable to
// recenter the view when arranging monitors that don't fit the window at
// once. A pan can't create an overlap (every tile moves together), so
// collision checking is skipped for it.
//
// Dragging is tracked manually (mouse deltas accumulated into root.x/y)
// rather than via MouseArea.drag.target — target's x/y here would
// otherwise be a QML binding, and drag.target's job is to override exactly
// that kind of binding by writing to it directly, which this environment's
// Quickshell/Qt build was not reliably doing (tiles wouldn't move at all).
//
// targetRect (below) is deliberately NOT bound straight to x/y either, for
// the same reason: mixing a live declarative binding with the drag code's
// imperative writes to the same property is exactly the kind of thing that
// behaved inconsistently here. Position is synced from targetRect
// explicitly instead (syncPosition()), and only when not mid-drag.
Rectangle {
  id: root

  property bool selected: false
  property bool isPrimary: false
  property string label: ""
  property real pxPerUnit: 1
  // {x, y, width, height} in canvas pixels, as computed by the parent from
  // this tile's monitor data. Applied via syncPosition()/syncSize() below.
  property var targetRect: ({ x: 0, y: 0, width: 0, height: 0 })
  // Other tiles' current canvas-pixel rects, for drag collision checks.
  // Provided by the parent; excludes this tile. Unused while dragging the
  // primary (a pan can't introduce an overlap).
  property var obstacles: []

  signal tapped()
  signal moved(real dxUnits, real dyUnits)
  signal panned(real dxUnits, real dyUnits)
  signal primaryRequested()

  function syncSize() {
    width = targetRect.width
    height = targetRect.height
  }

  function syncPosition() {
    if (dragArea.dragging) return
    x = targetRect.x
    y = targetRect.y
  }

  onTargetRectChanged: { syncSize(); syncPosition() }
  Component.onCompleted: { syncSize(); syncPosition() }

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

  // Pin badge: filled/accented when this tile is primary (the (0,0)
  // anchor); click any other tile's badge to make that one primary
  // instead (rebasing every monitor's coordinates around it).
  Rectangle {
    id: pin
    // Above dragArea (declared after it, and geometrically overlapping the
    // corner) so its MouseArea gets first crack at clicks there.
    z: 10
    width: Style.space(18)
    height: Style.space(18)
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: Style.space(4)
    radius: width / 2
    color: root.isPrimary
      ? Color.accent
      : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55)
    border.color: Color.accent
    border.width: 1

    Text {
      anchors.centerIn: parent
      text: "★"
      font.pixelSize: Style.font.caption
      color: root.isPrimary ? Color.background : Color.accent
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.tapped(); root.primaryRequested() }
    }
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    cursorShape: root.isPrimary ? Qt.OpenHandCursor : Qt.SizeAllCursor
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
      root.tapped()
      pressLocalX = mouse.x
      pressLocalY = mouse.y
      startTileX = root.x
      startTileY = root.y
      dragging = true
    }

    onPositionChanged: function(mouse) {
      if (!dragging) return
      var candidateX = root.x + (mouse.x - pressLocalX)
      var candidateY = root.y + (mouse.y - pressLocalY)

      if (root.isPrimary) {
        // Panning: every tile moves together, so there's nothing to block.
        root.x = candidateX
        root.y = candidateY
        return
      }

      // Resolved per axis rather than as one all-or-nothing (x,y) pair: a
      // real layout usually starts with monitors touching edge-to-edge, so
      // almost any drag direction immediately collides on whichever axis
      // points at a neighbor. Rejecting the whole move for that pinned the
      // tile at its start position for the entire gesture in testing (every
      // candidate blocked). Resolving x and y separately lets the tile
      // still slide along the free axis instead of freezing solid.
      var nextX = root.collidesAt(candidateX, root.y) ? root.x : candidateX
      var nextY = root.collidesAt(nextX, candidateY) ? root.y : candidateY
      root.x = nextX
      root.y = nextY
    }

    onReleased: {
      if (!dragging) return
      dragging = false
      // Guards divide-by-zero only -- NOT a floor on legitimate values.
      // pxPerUnit is routinely well under 1 (a multi-monitor layout spans
      // thousands of units rendered into a canvas a few hundred pixels
      // wide); Math.max(1, ...) here previously clamped it up to 1 in
      // exactly that common case, corrupting every delta computed below.
      var safePxPerUnit = Math.max(0.000001, root.pxPerUnit)
      var dxUnits = (root.x - startTileX) / safePxPerUnit
      var dyUnits = (root.y - startTileY) / safePxPerUnit
      if (dxUnits === 0 && dyUnits === 0) return
      if (root.isPrimary) root.panned(dxUnits, dyUnits)
      else root.moved(dxUnits, dyUnits)
      // The parent updates the model (or, for a pan, the canvas origin) on
      // this signal, which comes back around as a new targetRect;
      // syncPosition() then applies it (dragging is false by then) —
      // normally a no-op since it should already match, but it's what
      // settles a drop onto its exact rounded-unit grid position.
    }
  }
}
