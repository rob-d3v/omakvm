import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui
import "Net.js" as Net

// Bar icon: two screens side by side. The second one fills in while this PC's
// keyboard and mouse are on a network PC. Left click opens the panel, right
// click Mickey's switcher (one card per PC), middle click brings the keyboard
// home.
BarWidget {
  id: root
  moduleName: "io.github.rob-d3v.omakvm"

  // "off": Mickey is not running (or not installed); "local"; "remote".
  property string kbState: "off"
  property string kbPeer: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // `mickey status --waybar` prints one JSON line now and one more each time
  // the keyboard moves or a PC comes or goes: no polling.
  Process {
    id: follow
    running: true
    command: ["sh", "-c", 'PATH="$HOME/.local/bin:$PATH"; command -v mickey >/dev/null 2>&1 || exit 127; exec mickey status --waybar']
    stdout: SplitParser {
      onRead: function(line) {
        var s = Net.parseWaybar(line)
        root.kbState = s.state
        root.kbPeer = s.focus
      }
    }
    onExited: function(code) {
      root.kbState = "off"
      root.kbPeer = ""
      retry.interval = code === 127 ? 60000 : 5000
      retry.restart()
    }
  }

  Timer {
    id: retry
    interval: 5000
    onTriggered: follow.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        readonly property real stroke: Math.max(1.5, width / 12)
        Rectangle {
          x: 0
          y: parent.height * 0.2
          width: parent.width * 0.46
          height: parent.height * 0.6
          radius: 2
          color: "transparent"
          border.width: parent.stroke
          border.color: button.foreground
        }
        Rectangle {
          x: parent.width * 0.54
          y: parent.height * 0.3
          width: parent.width * 0.46
          height: parent.height * 0.4
          radius: 2
          color: root.kbState === "remote" ? button.foreground : "transparent"
          border.width: parent.stroke
          border.color: button.foreground
          opacity: root.kbState === "off" ? 0.45 : 1
        }
      }
    }
    tooltipText: root.kbState === "remote" ? strings.t("bar.remote").arg(Net.noMarkup(root.kbPeer))
               : root.kbState === "local" ? strings.t("bar.local")
               : strings.t("bar.off")
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run('PATH="$HOME/.local/bin:$PATH"; mickey switcher')
      else if (b === Qt.MiddleButton) root.bar.run('PATH="$HOME/.local/bin:$PATH"; mickey home')
      else root.bar.run("omarchy-shell shell toggle io.github.rob-d3v.omakvm")
    }
  }
}
