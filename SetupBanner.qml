import QtQuick
import qs.Commons

// Shown when hyprland.lua doesn't yet load the file this plugin writes on
// Apply/Save — Apply and Save still work fine either way (they're just
// file writes), but without this nothing a profile changes ever reaches
// the screen, which reads as the plugin doing nothing. Every fresh
// install needs this once.
Item {
  id: root

  signal wireUpRequested()
  signal dismissed()

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(420))
    spacing: Style.space(14)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Setup required"
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Style.font.heading
      color: Color.foreground
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      text: "Hyprland's config doesn't load this plugin's monitor layouts yet. " +
        "Add one line to ~/.config/hypr/hyprland.lua, right after require(\"hypr.monitors\"):"
    }

    Rectangle {
      width: parent.width
      height: Style.space(34)
      radius: Style.cornerRadius
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
      border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: 'pcall(require, "hypr.hypr_screen")'
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        color: Color.accent
      }
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: addButtonLabel.implicitWidth + Style.space(28)
      height: Style.space(32)
      radius: Style.cornerRadius
      color: addButtonArea.pressed
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
        : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20)
      border.color: Color.accent
      border.width: 1

      Text {
        id: addButtonLabel
        anchors.centerIn: parent
        text: "Add it for me"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: addButtonArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.wireUpRequested()
      }
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
