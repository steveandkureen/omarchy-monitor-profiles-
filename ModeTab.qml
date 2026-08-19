import QtQuick
import qs.Commons

Rectangle {
  id: root
  property string label: ""
  property bool active: false
  signal selected()

  width: Style.space(64)
  height: Style.space(24)
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  radius: Style.cornerRadius
  color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : "transparent"
  border.color: active ? Color.accent : Color.muted
  border.width: 1

  Text {
    anchors.centerIn: parent
    text: root.label
    color: root.active ? Color.foreground : Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: root.active
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.selected()
  }
}
