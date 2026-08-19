import QtQuick
import qs.Commons

Rectangle {
  id: root
  property string text: ""
  signal clicked()

  width: Style.space(70)
  height: Style.space(30)
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  radius: Style.cornerRadius
  color: area.pressed
    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
    : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20)
  border.color: Color.accent
  border.width: 1

  Text {
    anchors.centerIn: parent
    text: root.text
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  MouseArea {
    id: area
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
