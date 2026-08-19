import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// Standalone panel plugin (kind: "panel"): summoned via keybind/IPC, not
// hosted by a bar widget. Contract: opened/open(payloadJson)/close(), plus
// shell/manifest injected by the host — see wifiqr and the plugin dev guide
// for the pattern this follows.
//
// Payload: {"mode": "switcher"|"editor", "timeout": <seconds>}
// Default mode is "editor" (equivalent to running the old app with no args);
// the SUPER+SHIFT+P keybind summons with {"mode":"switcher"} (equivalent to
// the old --next).
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string mode: "editor"
  property int switcherTimeout: 10

  readonly property string home: Quickshell.env("HOME")
  readonly property string profilesDir: root.home + "/.config/hypr/profiles"
  readonly property string hyprScreenLuaPath: root.home + "/.config/hypr/hypr_screen.lua"
  readonly property string pluginId: (root.manifest && root.manifest.id) || "dev.stephenschwarz.monitor-profiles"

  property var switcherProfiles: []

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.mode = payload.mode === "switcher" ? "switcher" : "editor"
    root.switcherTimeout = payload.timeout !== undefined ? Number(payload.timeout) : 10
    if (root.mode === "switcher") refreshSwitcherProfiles()
    root.opened = true
    Qt.callLater(root.focusActiveView)
  }

  // Keyboard nav (SwitcherView's arrow keys/Enter) only fires while that
  // item itself holds activeFocus — QML key events bubble up from whichever
  // item is focused, never down into children, so focusing keyCatcher here
  // would silently swallow those keys instead of reaching the switcher.
  function focusActiveView() {
    if (!root.opened) return
    if (root.mode === "switcher") switcherView.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else close()
  }

  function setMode(next) {
    root.mode = next
    if (next === "switcher") refreshSwitcherProfiles()
    Qt.callLater(root.focusActiveView)
  }

  function refreshSwitcherProfiles() {
    switcherListProc.running = false
    switcherListProc.running = true
  }

  // Apply a saved profile by name: read it, translate to Lua, reload, then
  // dismiss — the switcher's Enter action. Kept independent of EditorView's
  // in-progress edit state.
  function applyProfileByName(name) {
    switcherApplyFile.path = root.profilesDir + "/" + name + ".conf"
    switcherApplyFile.reload()
    switcherApplyTarget = name
  }

  property string switcherApplyTarget: ""

  Process {
    id: switcherListProc
    command: ["bash", "-lc", "ls -1 \"" + root.profilesDir + "\" 2>/dev/null | grep '\\.conf$'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(l) { return l.trim() !== "" })
        root.switcherProfiles = lines.map(function(l) { return l.replace(/\.conf$/, "") })
      }
    }
  }

  FileView {
    id: switcherApplyFile
    watchChanges: false
    printErrors: false
    onLoaded: {
      var monitors = Model.parseProfileText(text())
      if (monitors.length === 0) return
      applyLuaFile.path = root.hyprScreenLuaPath
      applyLuaFile.setText(Model.profileToLua(monitors, root.switcherApplyTarget))
      switcherReloadProc.running = true
    }
  }

  FileView {
    id: applyLuaFile
    watchChanges: false
    printErrors: false
  }

  Process {
    id: switcherReloadProc
    command: ["hyprctl", "reload"]
    onExited: root.dismiss()
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "monitor-profiles"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Item {
        anchors.centerIn: parent
        readonly property real cardWidth: root.mode === "switcher" ? Style.space(420) : Style.space(980)
        readonly property real cardHeight: root.mode === "switcher" ? Style.space(480) : Style.space(680)
        width: cardWidth
        height: cardHeight
        scale: Math.min(1,
          (keyCatcher.width - Style.space(32)) / Math.max(1, cardWidth),
          (keyCatcher.height - Style.space(32)) / Math.max(1, cardHeight))

        MouseArea { anchors.fill: parent; onClicked: {} } // swallow: only the scrim dismisses

        Rectangle {
          id: card
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: Color.popups.border
          border.width: 1

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Row {
              width: parent.width
              height: Style.space(28)
              spacing: Style.space(8)

              Text {
                text: "Monitor Profiles"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item { width: Style.space(8); height: 1 }

              ModeTab { label: "Switch"; active: root.mode === "switcher"; onSelected: root.setMode("switcher") }
              ModeTab { label: "Edit"; active: root.mode === "editor"; onSelected: root.setMode("editor") }
            }

            Item {
              width: parent.width
              height: parent.height - Style.space(38)

              SwitcherView {
                id: switcherView
                anchors.fill: parent
                visible: root.mode === "switcher"
                profiles: root.switcherProfiles
                timeoutSeconds: root.switcherTimeout
                onApplyRequested: function(name) { root.applyProfileByName(name) }
              }

              EditorView {
                anchors.fill: parent
                visible: root.mode === "editor"
              }
            }
          }
        }
      }
    }
  }
}
