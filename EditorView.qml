import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// The visual editor: a sidebar of saved profiles plus a draggable canvas of
// monitor tiles, with a property inspector for the selected monitor.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string profilesDir: root.home + "/.config/hypr/profiles"
  readonly property string hyprScreenLuaPath: root.home + "/.config/hypr/hypr_screen.lua"

  property var monitors: []
  property var profileNames: []
  property string profileName: ""
  property int selectedMonitorIndex: -1
  // Set by Panel.qml, bumped when it seeds a first-run profile behind our
  // back (both views can be the first one opened) — refresh to pick it up.
  property int profilesRevision: 0
  onProfilesRevisionChanged: refreshProfileList()
  readonly property var selectedMonitor: selectedMonitorIndex >= 0 && selectedMonitorIndex < monitors.length
    ? monitors[selectedMonitorIndex] : null

  // The primary monitor's tile is not draggable and stays put; every other
  // tile drags relative to it. Defaults to whichever monitor is already at
  // (0,0) (the usual case for a real layout), else the first one.
  property int primaryIndex: 0

  function setPrimary(newIndex) {
    if (newIndex < 0 || newIndex >= root.monitors.length || newIndex === root.primaryIndex) return
    var offsetXUnits = root.monitors[newIndex].x
    var offsetYUnits = root.monitors[newIndex].y
    if (offsetXUnits !== 0 || offsetYUnits !== 0) {
      root.monitors = root.monitors.map(function(m) {
        return Object.assign({}, m, { x: m.x - offsetXUnits, y: m.y - offsetYUnits })
      })
    }
    root.primaryIndex = newIndex
    canvasArea.recomputeBounds()
  }

  property string statusText: ""

  signal applied()

  // ---- keyboard-only editing -------------------------------------------
  //
  // "normal": h/j/k/l (or arrows) move the *selection* to the nearest tile
  //   in that direction — same idea as Hyprland's own movefocus. i enters
  //   move mode on the selected tile (selecting the first one first if
  //   none is selected yet). Everything else is a single mnemonic key; see
  //   the hint row at the bottom of the canvas, which always shows the
  //   current mode's bindings.
  // "move": h/j/k/l nudge the selected tile (or pan the canvas, if it's
  //   the primary — same distinction as dragging it with the mouse). Hold
  //   Shift for a finer step. Esc returns to normal without needing to
  //   "confirm" — each nudge already committed to root.monitors when it
  //   happened, same as a mouse drag committing on release.
  // "naming": the profile name field has focus; Enter saves, Esc cancels.
  property string editorMode: "normal"
  readonly property real moveStepUnits: 80
  readonly property real moveStepFineUnits: 10

  function selectDirection(dir) {
    if (root.monitors.length === 0) return
    if (root.selectedMonitorIndex < 0 || root.selectedMonitorIndex >= root.monitors.length) {
      root.selectedMonitorIndex = 0
      return
    }
    var current = canvasArea.rectFor(root.monitors[root.selectedMonitorIndex])
    var cx = current.x + current.width / 2
    var cy = current.y + current.height / 2
    var best = -1
    var bestScore = Infinity
    for (var i = 0; i < root.monitors.length; i++) {
      if (i === root.selectedMonitorIndex) continue
      var r = canvasArea.rectFor(root.monitors[i])
      var dx = (r.x + r.width / 2) - cx
      var dy = (r.y + r.height / 2) - cy
      var primary, lateral
      if (dir === "left") { if (dx >= -1) continue; primary = -dx; lateral = Math.abs(dy) }
      else if (dir === "right") { if (dx <= 1) continue; primary = dx; lateral = Math.abs(dy) }
      else if (dir === "up") { if (dy >= -1) continue; primary = -dy; lateral = Math.abs(dx) }
      else { if (dy <= 1) continue; primary = dy; lateral = Math.abs(dx) }
      // Favor the tile mostly in the requested direction over one that's
      // merely closer but well off to the side — weighting lateral offset
      // more than direct distance is what keeps e.g. "up" from jumping
      // sideways to a nearer tile that isn't really above you.
      var score = primary + lateral * 2
      if (score < bestScore) { bestScore = score; best = i }
    }
    if (best >= 0) root.selectedMonitorIndex = best
  }

  function collidesAtUnits(index, xUnits, yUnits) {
    var m = root.monitors[index]
    var w = (m.transform % 2 === 1) ? m.height / m.scale : m.width / m.scale
    var h = (m.transform % 2 === 1) ? m.width / m.scale : m.height / m.scale
    var ax1 = xUnits, ax2 = xUnits + w, ay1 = yUnits, ay2 = yUnits + h
    for (var i = 0; i < root.monitors.length; i++) {
      if (i === index) continue
      var o = root.monitors[i]
      var ow = (o.transform % 2 === 1) ? o.height / o.scale : o.width / o.scale
      var oh = (o.transform % 2 === 1) ? o.width / o.scale : o.height / o.scale
      var bx1 = o.x, bx2 = o.x + ow, by1 = o.y, by2 = o.y + oh
      if (ax1 < bx2 && ax2 > bx1 && ay1 < by2 && ay2 > by1) return true
    }
    return false
  }

  function nudgeSelected(dxUnits, dyUnits) {
    var idx = root.selectedMonitorIndex
    if (idx < 0 || idx >= root.monitors.length) return
    if (idx === root.primaryIndex) {
      // Same distinction as dragging it with the mouse: the primary stays
      // at (0,0) in the data, so "moving" it pans the shared frame instead.
      canvasArea.boundMinX -= dxUnits
      canvasArea.boundMinY -= dyUnits
      return
    }
    var m = root.monitors[idx]
    var candidateX = m.x + dxUnits
    var candidateY = m.y + dyUnits
    if (root.collidesAtUnits(idx, candidateX, candidateY)) return
    var next = root.monitors.slice()
    next[idx] = Object.assign({}, m, { x: Math.round(candidateX), y: Math.round(candidateY) })
    root.monitors = next
  }

  function toggleEnabledSelected() {
    if (root.selectedMonitor) root.updateSelected({ enabled: !root.selectedMonitor.enabled })
  }

  function rotateSelected() {
    if (root.selectedMonitor) root.updateSelected({ transform: (root.selectedMonitor.transform + 1) % 4 })
  }

  function cycleProfile(delta) {
    if (root.profileNames.length === 0) return
    var i = root.profileNames.indexOf(root.profileName)
    var next = i < 0
      ? (delta > 0 ? 0 : root.profileNames.length - 1)
      : (i + delta + root.profileNames.length) % root.profileNames.length
    root.loadProfile(root.profileNames[next])
  }

  function deleteCurrentProfile() {
    if (root.profileNames.indexOf(root.profileName) < 0) return
    root.deleteProfile(root.profileName)
  }

  function saveOrSaveAs() {
    if (root.profileName.trim() !== "") { root.saveProfile(); return }
    root.startSaveAs()
  }

  // Not a rename: this writes a new file under whatever name ends up in
  // nameInput and leaves the original profile (if any) untouched. Starting
  // the name pre-filled/selected just makes "tweak the name a little" as
  // easy as an actual rename would be.
  function startSaveAs() {
    root.editorMode = "naming"
    Qt.callLater(function() { nameInput.forceActiveFocus(); nameInput.selectAll() })
  }

  function finishNaming(shouldSave) {
    root.editorMode = "normal"
    if (shouldSave) root.saveProfile()
    root.forceActiveFocus()
  }

  function refreshProfileList() {
    listProc.running = false
    listProc.running = true
  }

  function loadLiveLayout() {
    liveProc.running = false
    liveProc.running = true
  }

  function loadProfile(name) {
    root.profileName = name
    profileFile.path = root.profilesDir + "/" + name + ".conf"
    profileFile.reload()
  }

  function replaceMonitors(next) {
    root.monitors = next
    if (root.selectedMonitorIndex >= next.length) root.selectedMonitorIndex = next.length > 0 ? 0 : -1
    var zeroIndex = -1
    for (var i = 0; i < next.length; i++) {
      if (next[i].x === 0 && next[i].y === 0) { zeroIndex = i; break }
    }
    root.primaryIndex = zeroIndex >= 0 ? zeroIndex : 0
    // Bounds/scale are frozen to this new layout, not recomputed on every
    // drag or field edit — see canvasArea.recomputeBounds() for why.
    canvasArea.recomputeBounds()
  }

  function updateSelected(fields) {
    if (root.selectedMonitorIndex < 0) return
    var next = root.monitors.slice()
    var m = Object.assign({}, next[root.selectedMonitorIndex], fields)
    next[root.selectedMonitorIndex] = m
    root.monitors = next
  }

  function saveProfile() {
    var name = root.profileName.trim()
    if (name === "") { root.statusText = "Name the profile before saving."; return }
    if (root.monitors.length === 0) { root.statusText = "Nothing to save."; return }
    profileFile.path = root.profilesDir + "/" + name + ".conf"
    profileFile.setText(Model.profileToText(root.monitors))
    root.statusText = "Saved \"" + name + "\"."
    mkdirProc.running = true
    Qt.callLater(root.refreshProfileList)
  }

  function deleteProfile(name) {
    deleteProc.command = ["rm", "-f", root.profilesDir + "/" + name + ".conf"]
    deleteProc.running = true
    if (root.profileName === name) root.profileName = ""
    Qt.callLater(root.refreshProfileList)
  }

  function applyNow() {
    if (root.monitors.length === 0) return
    applyFile.path = root.hyprScreenLuaPath
    applyFile.setText(Model.profileToLua(root.monitors, root.profileName))
    reloadProc.running = true
    root.statusText = "Applied."
    root.applied()
  }

  Component.onCompleted: {
    refreshProfileList()
    if (root.monitors.length === 0) loadLiveLayout()
  }

  // "dd" to delete, vim-style: the first d arms a short window for the
  // second one rather than deleting immediately on a single keystroke.
  property bool pendingDelete: false
  Timer { id: pendingDeleteTimer; interval: 650; onTriggered: root.pendingDelete = false }

  focus: true
  Keys.onPressed: function(event) {
    if (root.editorMode === "naming") return // nameInput has its own focus/handlers while active

    if (root.editorMode === "move") {
      var fine = (event.modifiers & Qt.ShiftModifier) !== 0
      var step = fine ? root.moveStepFineUnits : root.moveStepUnits
      if (event.key === Qt.Key_H || event.key === Qt.Key_Left) { root.nudgeSelected(-step, 0); event.accepted = true }
      else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) { root.nudgeSelected(step, 0); event.accepted = true }
      else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { root.nudgeSelected(0, -step); event.accepted = true }
      else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { root.nudgeSelected(0, step); event.accepted = true }
      else if (event.key === Qt.Key_Escape) { root.editorMode = "normal"; event.accepted = true }
      return
    }

    // normal mode
    if (event.key === Qt.Key_D) {
      if (root.pendingDelete) { root.pendingDelete = false; pendingDeleteTimer.stop(); root.deleteCurrentProfile() }
      else { root.pendingDelete = true; pendingDeleteTimer.restart() }
      event.accepted = true
      return
    }
    if (root.pendingDelete) { root.pendingDelete = false; pendingDeleteTimer.stop() } // any other key cancels "d"

    if (event.key === Qt.Key_H || event.key === Qt.Key_Left) { root.selectDirection("left"); event.accepted = true }
    else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) { root.selectDirection("right"); event.accepted = true }
    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { root.selectDirection("up"); event.accepted = true }
    else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { root.selectDirection("down"); event.accepted = true }
    else if (event.key === Qt.Key_I) {
      if (root.selectedMonitorIndex < 0 && root.monitors.length > 0) root.selectedMonitorIndex = 0
      if (root.selectedMonitorIndex >= 0) root.editorMode = "move"
      event.accepted = true
    }
    else if (event.key === Qt.Key_E) { root.toggleEnabledSelected(); event.accepted = true }
    else if (event.key === Qt.Key_R) {
      if (event.modifiers & Qt.ShiftModifier) root.startSaveAs()
      else root.rotateSelected()
      event.accepted = true
    }
    else if (event.key === Qt.Key_P) { if (root.selectedMonitorIndex >= 0) root.setPrimary(root.selectedMonitorIndex); event.accepted = true }
    else if (event.key === Qt.Key_BracketLeft) { root.cycleProfile(-1); event.accepted = true }
    else if (event.key === Qt.Key_BracketRight) { root.cycleProfile(1); event.accepted = true }
    else if (event.key === Qt.Key_N) { root.loadLiveLayout(); event.accepted = true }
    else if (event.key === Qt.Key_S) { root.saveOrSaveAs(); event.accepted = true }
    else if (event.key === Qt.Key_A) { root.applyNow(); event.accepted = true }
    // Escape is deliberately not handled here — unhandled, it bubbles up
    // to Panel.qml's keyCatcher, which dismisses the whole panel. That
    // matches every other "normal mode" in this plugin (nothing to back
    // out of locally) the same way Esc already works in the switcher.
  }

  // ---- process/file plumbing ----------------------------------------

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.profilesDir]
  }

  Process {
    id: listProc
    command: ["bash", "-lc", "ls -1 \"" + root.profilesDir + "\" 2>/dev/null | grep '\\.conf$'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(l) { return l.trim() !== "" })
        root.profileNames = lines.map(function(l) { return l.replace(/\.conf$/, "") })
      }
    }
  }

  Process {
    id: liveProc
    // "all" (not just active outputs) so a connected-but-disabled monitor —
    // e.g. one that dropped out, or one nothing has ever enabled — still
    // shows up as a tile you can enable and position, not just ones
    // currently on screen.
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.replaceMonitors(parsed.map(Model.monitorFromHyprctlJson))
          root.profileName = ""
          root.statusText = "Loaded connected monitors (" + parsed.length + ")."
        } catch (e) {
          root.statusText = "Could not read hyprctl monitors: " + e
        }
      }
    }
  }

  Process {
    id: deleteProc
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
  }

  FileView {
    id: profileFile
    watchChanges: false
    printErrors: false
    onLoaded: {
      var parsed = Model.parseProfileText(text())
      if (parsed.length > 0) root.replaceMonitors(parsed)
    }
  }

  FileView {
    id: applyFile
    watchChanges: false
    printErrors: false
  }

  // ---- layout ---------------------------------------------------------

  Row {
    anchors.fill: parent
    spacing: 0

    // Sidebar: saved profiles.
    Rectangle {
      width: Style.space(180)
      height: parent.height
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(6)

        Text {
          text: "Profiles"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.profileNames

          Rectangle {
            id: profileRow
            required property string modelData
            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            color: profileRow.modelData === root.profileName
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
              : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: deleteBtn.left
              anchors.verticalCenter: parent.verticalCenter
              text: profileRow.modelData
              elide: Text.ElideRight
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              id: deleteBtn
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              color: Color.urgent
              font.pixelSize: Style.font.caption
              MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.deleteProfile(profileRow.modelData) }
            }

            MouseArea {
              anchors.fill: parent
              anchors.rightMargin: Style.space(20)
              onClicked: root.loadProfile(profileRow.modelData)
            }
          }
        }

        Item { width: 1; height: Style.space(4) }

        Rectangle {
          width: parent.width
          height: Style.space(30)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          Text {
            anchors.centerIn: parent
            text: "Load current layout"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          MouseArea { anchors.fill: parent; onClicked: root.loadLiveLayout() }
        }
      }
    }

    // Canvas + inspector.
    Column {
      width: parent.width - Style.space(180)
      height: parent.height
      spacing: 0

      Item {
        id: canvasArea
        width: parent.width
        height: parent.height - hintBar.height - inspector.height - saveBar.height

        readonly property real margin: Style.space(24)
        // Fraction of the scale-to-fit size tiles actually render at, so
        // they don't butt up against the canvas edge and there's slack to
        // drag them around in.
        readonly property real fitScale: 0.7

        // Frozen at load time (see recomputeBounds()) rather than derived
        // live from root.monitors: if these tracked every drag/field edit,
        // moving one tile would shift every tile's frame of reference
        // (scale + origin) out from under it as soon as you dropped it —
        // the "snaps back" symptom. A stable frame is what makes a drop
        // land, and stay, where you dropped it.
        property real boundMinX: 0
        property real boundMinY: 0
        property real boundWidth: 1
        property real boundHeight: 1

        function recomputeBounds() {
          var monitors = root.monitors
          if (!monitors.length) {
            boundMinX = 0; boundMinY = 0; boundWidth = 1; boundHeight = 1
            return
          }
          var minX = Math.min.apply(null, monitors.map(function(m) { return m.x }))
          var minY = Math.min.apply(null, monitors.map(function(m) { return m.y }))
          var maxX = Math.max.apply(null, monitors.map(function(m) {
            var w = (m.transform % 2 === 1) ? m.height / m.scale : m.width / m.scale
            return m.x + w
          }))
          var maxY = Math.max.apply(null, monitors.map(function(m) {
            var h = (m.transform % 2 === 1) ? m.width / m.scale : m.height / m.scale
            return m.y + h
          }))
          boundMinX = minX
          boundMinY = minY
          boundWidth = Math.max(1, maxX - minX)
          boundHeight = Math.max(1, maxY - minY)
        }

        readonly property real pxPerUnit: fitScale * Math.min(
          (width - 2 * margin) / boundWidth,
          (height - 2 * margin) / boundHeight)
        readonly property real offsetX: (width - boundWidth * pxPerUnit) / 2
        readonly property real offsetY: (height - boundHeight * pxPerUnit) / 2

        // Canvas-pixel geometry for a monitor object, shared by each tile's
        // own placement and by its siblings' collision obstacle lists.
        function rectFor(m) {
          var w = (m.transform % 2 === 1) ? m.height / m.scale : m.width / m.scale
          var h = (m.transform % 2 === 1) ? m.width / m.scale : m.height / m.scale
          return {
            x: offsetX + (m.x - boundMinX) * pxPerUnit,
            y: offsetY + (m.y - boundMinY) * pxPerUnit,
            width: w * pxPerUnit,
            height: h * pxPerUnit
          }
        }

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
          border.width: 1
          radius: Style.cornerRadius
        }

        Repeater {
          model: root.monitors

          MonitorRect {
            id: tile
            required property int index
            required property var modelData

            targetRect: canvasArea.rectFor(modelData)
            pxPerUnit: canvasArea.pxPerUnit
            selected: index === root.selectedMonitorIndex
            isPrimary: index === root.primaryIndex
            label: modelData.name + "\n" + modelData.width + "x" + modelData.height + (modelData.enabled ? "" : " (off)")
            opacity: modelData.enabled ? 1.0 : 0.4
            obstacles: {
              var list = []
              for (var i = 0; i < root.monitors.length; i++) {
                if (i !== index) list.push(canvasArea.rectFor(root.monitors[i]))
              }
              return list
            }

            onTapped: root.selectedMonitorIndex = index
            onPrimaryRequested: root.setPrimary(index)
            onMoved: function(dxUnits, dyUnits) {
              var next = root.monitors.slice()
              var m = Object.assign({}, next[index])
              m.x = Math.round(m.x + dxUnits)
              m.y = Math.round(m.y + dyUnits)
              next[index] = m
              root.monitors = next
            }
            // Dragging the primary pans the view instead of moving it in
            // the layout (it stays the (0,0) anchor) — shift the shared
            // origin every tile renders relative to, not any monitor's
            // data, so Save/Apply are unaffected by how the canvas is
            // scrolled.
            onPanned: function(dxUnits, dyUnits) {
              canvasArea.boundMinX -= dxUnits
              canvasArea.boundMinY -= dyUnits
            }
          }
        }
      }

      // Keyboard-mode hint line. Fixed height for the same reason as the
      // inspector below — canvasArea's frame must not move just because
      // the hint text changed length switching modes.
      Item {
        id: hintBar
        width: parent.width
        height: Style.space(20)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          text: {
            if (root.editorMode === "move")
              return "MOVE  hjkl/⇧hjkl nudge · esc done"
            if (root.editorMode === "naming")
              return "NAME  enter save · esc cancel"
            return "hjkl select · i move · r rotate · e enable · p primary · [ ] profile · s save · a apply · dd delete · q quit"
          }
        }
      }

      // Inspector for the selected monitor. Height is constant (not tied to
      // whether something is selected) so canvasArea's size — and so the
      // whole canvas-pixel coordinate frame every tile positions itself in
      // — never shifts as a side effect of selecting/deselecting a tile.
      // It used to, and since every press selects a tile before a drag
      // starts, that shift was corrupting the dragged tile's own position
      // baseline before the drag even began.
      Row {
        id: inspector
        width: parent.width
        height: Style.space(56)
        opacity: root.selectedMonitor !== null ? 1 : 0
        enabled: root.selectedMonitor !== null
        spacing: Style.space(10)
        leftPadding: Style.space(10)
        topPadding: Style.space(8)

        Text {
          text: root.selectedMonitor ? root.selectedMonitor.name : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        InspectorField {
          label: "W"
          value: root.selectedMonitor ? String(root.selectedMonitor.width) : ""
          onCommitted: function(v) { root.updateSelected({ width: parseInt(v, 10) || 0 }) }
        }
        InspectorField {
          label: "H"
          value: root.selectedMonitor ? String(root.selectedMonitor.height) : ""
          onCommitted: function(v) { root.updateSelected({ height: parseInt(v, 10) || 0 }) }
        }
        InspectorField {
          label: "Hz"
          value: root.selectedMonitor ? String(root.selectedMonitor.refresh) : ""
          onCommitted: function(v) { root.updateSelected({ refresh: parseFloat(v) || 60 }) }
        }
        InspectorField {
          label: "Scale"
          value: root.selectedMonitor ? String(root.selectedMonitor.scale) : ""
          onCommitted: function(v) { root.updateSelected({ scale: parseFloat(v) || 1.0 }) }
        }

        Text {
          text: "Rotate"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: Style.space(34); height: Style.space(24)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
          anchors.verticalCenter: parent.verticalCenter
          Text { anchors.centerIn: parent; text: root.selectedMonitor ? (root.selectedMonitor.transform * 90) + "°" : ""; color: Color.foreground; font.pixelSize: Style.font.caption }
          MouseArea {
            anchors.fill: parent
            onClicked: root.updateSelected({ transform: ((root.selectedMonitor.transform + 1) % 4) })
          }
        }

        Rectangle {
          width: Style.space(60); height: Style.space(24)
          radius: Style.cornerRadius
          anchors.verticalCenter: parent.verticalCenter
          color: root.selectedMonitor && root.selectedMonitor.enabled
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
            : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.25)
          Text {
            anchors.centerIn: parent
            text: root.selectedMonitor && root.selectedMonitor.enabled ? "Enabled" : "Disabled"
            color: Color.foreground
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            anchors.fill: parent
            onClicked: root.updateSelected({ enabled: !root.selectedMonitor.enabled })
          }
        }
      }

      // Save / apply bar.
      Row {
        id: saveBar
        width: parent.width
        height: Style.space(48)
        spacing: Style.space(8)
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)

        Rectangle {
          width: Style.space(180); height: Style.space(30)
          anchors.verticalCenter: parent.verticalCenter
          radius: Style.cornerRadius
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
          border.width: 1

          TextInput {
            id: nameInput
            anchors.fill: parent
            anchors.margins: Style.space(6)
            verticalAlignment: TextInput.AlignVCenter
            text: root.profileName
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            selectByMouse: true
            onTextEdited: root.profileName = text
            // Only meaningful while "naming" mode has given this field
            // focus (typing "s"/Shift+R from normal mode) — a plain mouse
            // click into the field still works too, just without the
            // mode's Enter/Esc conventions.
            Keys.onReturnPressed: root.finishNaming(true)
            Keys.onEnterPressed: root.finishNaming(true)
            Keys.onEscapePressed: root.finishNaming(false)
            Text {
              visible: parent.text === ""
              text: "profile name…"
              color: Color.muted
              font: parent.font
            }
          }
        }

        ActionButton { text: "Save"; onClicked: root.saveProfile() }
        ActionButton { text: "Apply"; onClicked: root.applyNow() }

        Text {
          text: root.statusText
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
