import QtQuick
import qs.Commons

// One row of SetupBanner's checklist: either "done" (a quiet checkmark
// line) or the description/snippet/button for fixing it.
Column {
  id: root

  property bool done: false
  property string title: ""
  property string body: ""
  property string snippet: ""
  property string doneText: ""

  signal addRequested()

  spacing: Style.space(6)

  Row {
    spacing: Style.space(6)
    Text {
      text: root.done ? "✓" : "○"
      color: root.done ? Color.accent : Color.muted
      font.pixelSize: Style.font.bodySmall
      font.bold: root.done
    }
    Text {
      text: root.done ? (root.title + " — " + root.doneText) : root.title
      color: root.done ? Color.muted : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: !root.done
    }
  }

  Column {
    width: root.width
    leftPadding: Style.space(18)
    spacing: Style.space(8)
    visible: !root.done

    Text {
      width: parent.width - parent.leftPadding
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: root.body
    }

    Rectangle {
      width: parent.width - parent.leftPadding
      height: Style.space(30)
      radius: Style.cornerRadius
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
      border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: root.snippet
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        color: Color.accent
      }
    }

    Rectangle {
      width: addLabel.implicitWidth + Style.space(24)
      height: Style.space(26)
      radius: Style.cornerRadius
      color: addArea.pressed
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
        : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20)
      border.color: Color.accent
      border.width: 1

      Text {
        id: addLabel
        anchors.centerIn: parent
        text: "Add it for me"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      MouseArea {
        id: addArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addRequested()
      }
    }
  }
}
