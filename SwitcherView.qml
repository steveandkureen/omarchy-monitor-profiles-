import QtQuick
import qs.Commons

// The quick switcher: arrow keys (or j/k) move the selection, Enter applies
// it. An optional auto-advance timer applies the current selection if left
// untouched, matching the old --next --timeout behavior.
Item {
  id: root

  property var profiles: []
  property int selectedIndex: 0
  property int timeoutSeconds: 10
  property bool busy: false

  signal applyRequested(string profileName)

  function moveSelection(delta) {
    if (root.profiles.length === 0) return
    var next = (root.selectedIndex + delta) % root.profiles.length
    if (next < 0) next += root.profiles.length
    root.selectedIndex = next
    resetTimer()
  }

  function applySelected() {
    if (root.profiles.length === 0 || root.busy) return
    root.applyRequested(root.profiles[root.selectedIndex])
  }

  function resetTimer() {
    autoAdvanceTimer.stop()
    if (root.timeoutSeconds > 0 && root.profiles.length > 0) autoAdvanceTimer.restart()
  }

  onProfilesChanged: {
    if (selectedIndex >= profiles.length) selectedIndex = 0
    resetTimer()
  }
  onVisibleChanged: if (visible) resetTimer(); else autoAdvanceTimer.stop()

  Timer {
    id: autoAdvanceTimer
    interval: root.timeoutSeconds * 1000
    repeat: false
    onTriggered: root.applySelected()
  }

  focus: true
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.moveSelection(1); event.accepted = true }
    else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.moveSelection(-1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applySelected(); event.accepted = true }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(8)

    Text {
      visible: root.profiles.length === 0
      text: "No profiles saved yet — create one in the Edit tab."
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      width: parent.width
    }

    Repeater {
      model: root.profiles

      Rectangle {
        id: row
        required property int index
        required property string modelData

        width: parent.width
        height: Style.space(40)
        radius: Style.cornerRadius
        color: index === root.selectedIndex
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
          : "transparent"
        border.color: index === root.selectedIndex ? Color.accent : "transparent"
        border.width: 1

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: index === root.selectedIndex
        }

        MouseArea {
          anchors.fill: parent
          onClicked: { root.selectedIndex = row.index; root.resetTimer() }
          onDoubleClicked: root.applySelected()
        }
      }
    }
  }
}
