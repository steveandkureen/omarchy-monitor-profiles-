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
  readonly property string hyprlandLuaPath: root.home + "/.config/hypr/hyprland.lua"
  readonly property string pluginId: (root.manifest && root.manifest.id) || "dev.stephenschwarz.monitor-profiles"

  property var switcherProfiles: []
  // Bumped whenever profiles/*.conf changes for a reason EditorView's own
  // Component.onCompleted listing wouldn't catch — right now, just seeding
  // (below). EditorView refreshes its own list when this changes.
  property int profilesRevision: 0

  // Whether hyprland.lua actually loads hypr_screen.lua — without that,
  // Apply/Save work fine (they're just file writes) but nothing ever
  // reaches the screen. Every fresh install needs this once; re-checked on
  // every open so it clears itself up as soon as it's fixed, however that
  // happens (the button below, or by hand per the README).
  property bool configChecked: false
  property bool configReady: false
  // Sticky for the life of this shell process once set, not just this
  // open/close cycle — otherwise the switcher keybind would re-nag on
  // every single press until the user gets around to fixing it.
  property bool setupDismissed: false
  readonly property bool showSetupBanner: configChecked && !configReady && !setupDismissed

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.mode = payload.mode === "switcher" ? "switcher" : "editor"
    root.switcherTimeout = payload.timeout !== undefined ? Number(payload.timeout) : 10
    if (root.mode === "switcher") refreshSwitcherProfiles()
    checkConfig()
    ensureProfilesSeeded()
    root.opened = true
    Qt.callLater(root.focusActiveView)
  }

  // First run (no profiles saved anywhere yet, in either mode — a fresh
  // install, or someone who deleted everything): seed one called "current"
  // from the live layout, so the switcher isn't just an empty list and
  // there's an immediate, known-good profile to fall back to. Checked on
  // every open, but the profiles-exist guard below makes it a no-op past
  // the first time.
  function ensureProfilesSeeded() {
    seedMkdirProc.running = false
    seedMkdirProc.running = true
  }

  Process {
    id: seedMkdirProc
    command: ["mkdir", "-p", root.profilesDir]
    onExited: seedCheckProc.running = true
  }

  Process {
    id: seedCheckProc
    command: ["bash", "-lc", "ls -1 \"" + root.profilesDir + "\" 2>/dev/null | grep -c '\\.conf$'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var count = parseInt(String(text || "0").trim(), 10) || 0
        if (count === 0) seedLiveProc.running = true
      }
    }
  }

  Process {
    id: seedLiveProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          var monitors = parsed.map(Model.monitorFromHyprctlJson)
          if (monitors.length > 0) {
            seedFile.path = root.profilesDir + "/current.conf"
            seedFile.setText(Model.profileToText(monitors))
            root.refreshSwitcherProfiles()
            root.profilesRevision += 1
          }
        } catch (e) {
          // No monitors to read, or hyprctl unavailable — nothing to seed;
          // the switcher/editor's own "no profiles" states cover this.
        }
      }
    }
  }

  FileView {
    id: seedFile
    watchChanges: false
    printErrors: false
  }

  function checkConfig() {
    configCheckProc.running = false
    configCheckProc.running = true
  }

  function wireUpConfig() {
    configWireUpProc.running = false
    configWireUpProc.running = true
  }

  // Keyboard nav (SwitcherView's arrow keys/Enter) only fires while that
  // item itself holds activeFocus — QML key events bubble up from whichever
  // item is focused, never down into children, so focusing keyCatcher here
  // would silently swallow those keys instead of reaching the switcher.
  function focusActiveView() {
    if (!root.opened) return
    if (root.showSetupBanner) { keyCatcher.forceActiveFocus(); return }
    if (root.mode === "switcher") switcherView.forceActiveFocus()
    else editorView.forceActiveFocus()
  }
  // The config check is async, so showSetupBanner can flip after the
  // initial focusActiveView() call already ran (e.g. focus went to
  // switcherView before the check resolved) — re-settle focus whenever it
  // changes so Up/Down/Enter aren't landing on a now-hidden view.
  onShowSetupBannerChanged: Qt.callLater(focusActiveView)

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

  Process {
    id: configCheckProc
    command: ["bash", "-lc", "grep -q hypr_screen \"" + root.hyprlandLuaPath + "\" 2>/dev/null && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.configReady = String(text || "").trim() === "yes"
        root.configChecked = true
      }
    }
  }

  // Idempotent: re-running (e.g. a second click, or a stale button press
  // after it already succeeded) is a no-op past the grep guard. Inserts
  // right after require("hypr.monitors") when present — matching the
  // README's placement — and just appends otherwise, since anywhere in
  // hyprland.lua works for correctness; only the convention cares.
  Process {
    id: configWireUpProc
    command: ["bash", "-lc",
      "FILE=" + JSON.stringify(root.hyprlandLuaPath) + "; " +
      "grep -q hypr_screen \"$FILE\" 2>/dev/null && exit 0; " +
      "if grep -q 'require(\"hypr.monitors\")' \"$FILE\" 2>/dev/null; then " +
      "  sed -i '/require(\"hypr.monitors\")/a pcall(require, \"hypr.hypr_screen\")' \"$FILE\"; " +
      "else " +
      "  printf '\\npcall(require, \"hypr.hypr_screen\")\\n' >> \"$FILE\"; " +
      "fi"]
    onExited: {
      configReloadProc.running = true
    }
  }

  Process {
    id: configReloadProc
    command: ["hyprctl", "reload"]
    onExited: root.checkConfig()
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
      // Reached by bubbling: neither SwitcherView nor EditorView's own
      // Keys.onPressed claims Tab or Q, so an unhandled press lands here
      // regardless of which one currently has focus — switching modes, or
      // quitting, without a mouse, same as the Switch/Edit tabs or the
      // scrim click. (q not just Escape: the near-universal "close this"
      // key in vim-adjacent TUIs — less, man, lazygit, htop — even though
      // vim itself doesn't bind it that way. Doesn't fire while the
      // profile-name field has focus in Naming mode; that's a real text
      // field and "q" there is just the letter q.)
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab) {
          root.setMode(root.mode === "switcher" ? "editor" : "switcher")
          event.accepted = true
        } else if (event.key === Qt.Key_Q) {
          root.dismiss()
          event.accepted = true
        }
      }

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

              SetupBanner {
                anchors.fill: parent
                visible: root.showSetupBanner
                onWireUpRequested: root.wireUpConfig()
                onDismissed: root.setupDismissed = true
              }

              SwitcherView {
                id: switcherView
                anchors.fill: parent
                visible: root.mode === "switcher" && !root.showSetupBanner
                profiles: root.switcherProfiles
                // 0 disables the auto-advance timer. It stops on its own
                // when the view is hidden (SwitcherView's onVisibleChanged),
                // but that only catches showSetupBanner turning on *after*
                // the timer already started — force it off from this side
                // too, otherwise a summon that opens straight onto the
                // banner still counts down behind it and silently
                // applies+dismisses while it's showing.
                timeoutSeconds: root.showSetupBanner ? 0 : root.switcherTimeout
                onApplyRequested: function(name) { root.applyProfileByName(name) }
              }

              EditorView {
                id: editorView
                anchors.fill: parent
                visible: root.mode === "editor" && !root.showSetupBanner
                profilesRevision: root.profilesRevision
              }
            }
          }
        }
      }
    }
  }
}
