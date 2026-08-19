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
  readonly property var selectedMonitor: selectedMonitorIndex >= 0 && selectedMonitorIndex < monitors.length
    ? monitors[selectedMonitorIndex] : null

  property string statusText: ""

  signal applied()

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
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.replaceMonitors(parsed.map(Model.monitorFromHyprctlJson))
          root.profileName = ""
          root.statusText = "Loaded current monitor layout."
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
        height: parent.height - inspector.height - saveBar.height

        readonly property real margin: Style.space(24)
        readonly property real boundMinX: root.monitors.length ? Math.min.apply(null, root.monitors.map(function(m) { return m.x })) : 0
        readonly property real boundMinY: root.monitors.length ? Math.min.apply(null, root.monitors.map(function(m) { return m.y })) : 0
        readonly property real boundMaxX: root.monitors.length ? Math.max.apply(null, root.monitors.map(function(m) {
          var w = (m.transform % 2 === 1) ? m.height / m.scale : m.width / m.scale
          return m.x + w
        })) : 1
        readonly property real boundMaxY: root.monitors.length ? Math.max.apply(null, root.monitors.map(function(m) {
          var h = (m.transform % 2 === 1) ? m.width / m.scale : m.height / m.scale
          return m.y + h
        })) : 1
        readonly property real boundWidth: Math.max(1, boundMaxX - boundMinX)
        readonly property real boundHeight: Math.max(1, boundMaxY - boundMinY)
        readonly property real pxPerUnit: Math.min(
          (width - 2 * margin) / boundWidth,
          (height - 2 * margin) / boundHeight)
        readonly property real offsetX: (width - boundWidth * pxPerUnit) / 2
        readonly property real offsetY: (height - boundHeight * pxPerUnit) / 2

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

            width: ((modelData.transform % 2 === 1) ? modelData.height / modelData.scale : modelData.width / modelData.scale) * canvasArea.pxPerUnit
            height: ((modelData.transform % 2 === 1) ? modelData.width / modelData.scale : modelData.height / modelData.scale) * canvasArea.pxPerUnit
            x: canvasArea.offsetX + (modelData.x - canvasArea.boundMinX) * canvasArea.pxPerUnit
            y: canvasArea.offsetY + (modelData.y - canvasArea.boundMinY) * canvasArea.pxPerUnit
            pxPerUnit: canvasArea.pxPerUnit
            selected: index === root.selectedMonitorIndex
            label: modelData.name + "\n" + modelData.width + "x" + modelData.height + (modelData.enabled ? "" : " (off)")
            opacity: modelData.enabled ? 1.0 : 0.4

            onTapped: root.selectedMonitorIndex = index
            onMoved: function(dxUnits, dyUnits) {
              var next = root.monitors.slice()
              var m = Object.assign({}, next[index])
              m.x = Math.round(m.x + dxUnits)
              m.y = Math.round(m.y + dyUnits)
              next[index] = m
              root.monitors = next
            }
          }
        }
      }

      // Inspector for the selected monitor.
      Row {
        id: inspector
        width: parent.width
        height: root.selectedMonitor ? Style.space(56) : 0
        visible: root.selectedMonitor !== null
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
            anchors.fill: parent
            anchors.margins: Style.space(6)
            verticalAlignment: TextInput.AlignVCenter
            text: root.profileName
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            onTextEdited: root.profileName = text
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
