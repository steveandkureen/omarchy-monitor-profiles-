import QtQuick
import qs.Commons

// Small labeled numeric field for the monitor inspector row.
Row {
  id: root
  property string label: ""
  property string value: ""
  signal committed(string text)

  spacing: Style.space(4)
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined

  Text {
    text: root.label
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    anchors.verticalCenter: parent.verticalCenter
  }

  Rectangle {
    width: Style.space(48)
    height: Style.space(24)
    radius: Style.cornerRadius
    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
    border.color: input.activeFocus ? Color.accent : "transparent"
    border.width: 1

    TextInput {
      id: input
      anchors.fill: parent
      anchors.margins: Style.space(4)
      verticalAlignment: TextInput.AlignVCenter
      horizontalAlignment: TextInput.AlignHCenter
      text: root.value
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      selectByMouse: true
      onEditingFinished: root.committed(text)

      // Keep in sync when the underlying monitor changes (e.g. selection swap)
      // without clobbering an in-progress edit.
      Connections {
        target: root
        function onValueChanged() { if (!input.activeFocus) input.text = root.value }
      }
    }
  }
}
