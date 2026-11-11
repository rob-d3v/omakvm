import QtQuick
import qs.Commons

// Every text in the panel goes through this: names of PCs and screens come
// from the network and from hyprctl, and must never be read as rich text.
Text {
  textFormat: Text.PlainText
  color: Color.menu.text
  font.family: Style.font.family
  font.pixelSize: Style.font.body
}
