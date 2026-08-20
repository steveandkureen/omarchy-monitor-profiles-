import QtQuick
import qs.Commons

// Two independent first-run checklist items:
//  - hyprland.lua loading what this plugin writes on Apply/Save. Without
//    this, Apply/Save still work fine (they're just file writes), but
//    nothing ever reaches the screen, which reads as the plugin doing
//    nothing. Genuinely blocks functionality, so this banner shows
//    whenever it's outstanding.
//  - a keybind summoning this plugin. Omarchy has no manifest-level way
//    for a plugin to declare/register one (checked), so this is offered
//    the same "detect it, one click to fix it" way as the config item,
//    just aimed at bindings.lua instead. Doesn't block anything (the
//    switcher/editor are still reachable via the desktop entry or a
//    manual summon either way) — suggested, not required.
Item {
  id: root

  property bool configReady: false
  property bool keybindReady: false

  signal wireUpConfigRequested()
  signal wireUpKeybindRequested()
  signal dismissed()

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(440))
    spacing: Style.space(16)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.configReady ? "Suggested setup" : "Setup required"
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Style.font.heading
      color: Color.foreground
    }

    SetupItem {
      width: parent.width
      done: root.configReady
      title: "Apply monitor layouts"
      body: "Hyprland's config doesn't load this plugin's monitor layouts yet. Add one line to ~/.config/hypr/hyprland.lua, right after require(\"hypr.monitors\"):"
      snippet: 'pcall(require, "hypr.hypr_screen")'
      doneText: "hyprland.lua already loads it"
      onAddRequested: root.wireUpConfigRequested()
    }

    SetupItem {
      width: parent.width
      done: root.keybindReady
      title: "Open it with a keybind"
      body: "No keybind summons this plugin yet. Add SUPER+SHIFT+P to ~/.config/hypr/bindings.lua (freely changeable afterward):"
      snippet: "SUPER + SHIFT + P"
      doneText: "a keybind is already set"
      onAddRequested: root.wireUpKeybindRequested()
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Skip for now — browse and edit profiles without applying"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.underline: true

      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismissed()
      }
    }
  }
}
