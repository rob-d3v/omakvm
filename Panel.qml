import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Net.js" as Net

// omakvm: this PC's screens and the PCs on the network, on one canvas.
//
//   omarchy-shell shell toggle io.github.rob-d3v.omakvm
//
// The screens part is Monitor Manager by Fabio Cuccaro (MIT): drag, snap, try
// live, save to ~/.config/hypr/monitors.lua. The network PCs are Mickey's
// (https://github.com/EduardoMG12/mickey): each paired PC is a tile whose
// place is Mickey's `position` in ~/.config/mickey/config.toml, so the cursor
// crosses to it where the tiles touch. This panel only runs `mickey` commands
// and edits that file; it never sees a key or the clipboard.
//
// The host calls open(payloadJson) / close() and reads `opened`; it also
// injects `shell` right after the Loader resolves.
//
// All logic lives in Model.js and Net.js (tested under node). Screens and PCs
// are plain JS objects mutated in place, so every change bumps `revision`,
// which the bindings below depend on to re-evaluate.
Item {
  id: root

  property bool opened: false
  readonly property string selfId: "io.github.rob-d3v.omakvm"
  property var shell: null
  onShellChanged: {
    if (!root.opened && root.shell && root.shell.openPanelIds
        && root.shell.openPanelIds[root.selfId] === true)
      root.open("{}")
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
  readonly property string configPath: root.home + "/.config/hypr/monitors.lua"
  readonly property string mickeyConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config")) + "/mickey/config.toml"
  // The shell may have been started without ~/.local/bin, where Mickey's
  // installer puts it.
  readonly property string pathPrefix: 'PATH="$HOME/.local/bin:$PATH"; '
  readonly property int revertSeconds: 15
  readonly property int snapPx: 14

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ------------------------------------------------------------------ state

  property var monitors: []
  property int revision: 0
  property int selectedIndex: 0
  property var liveSnapshot: ({})
  property string configText: ""
  // False until monitors.lua has been read (a missing file counts as read), so
  // a failed read can never turn into saving a rebuilt-from-nothing file.
  property bool configReadable: false
  property string statusText: ""
  property bool snapEnabled: true
  property bool identifying: false

  // Network PCs. "missing": no mickey on this PC; "stopped": installed, not
  // running; "running".
  property var peers: []
  property string selectedPeer: ""
  property var livePeerSnapshot: ({})
  property string mickeyConfigText: ""
  property bool mickeyConfigReadable: false
  property string mickeyState: "unknown"
  property string mickeyVersion: ""
  property string focusPeer: ""
  property string peersRaw: ""
  property var discovered: []
  property bool adding: false
  property string confirmRemove: ""
  property bool pendingPeerSave: false

  // Undo/redo keep whole-layout snapshots; the depths are plain ints because
  // pushing to a JS array doesn't notify bindings.
  readonly property int undoLimit: 50
  property var undoStack: []
  property var redoStack: []
  property int undoDepth: 0
  property int redoDepth: 0

  readonly property var selected: {
    root.revision
    if (root.selectedPeer !== "") return null
    return root.monitors.length ? root.monitors[Math.min(root.selectedIndex, root.monitors.length - 1)] : null
  }
  readonly property var peer: {
    root.revision
    if (root.selectedPeer === "") return null
    return root.peers.find(function(p) { return p.name === root.selectedPeer }) || null
  }
  readonly property bool monitorsDirty: {
    root.revision
    return !Model.sameSnapshot(Model.snapshot(root.monitors), root.liveSnapshot)
  }
  readonly property bool peersDirty: {
    root.revision
    return !Net.sameSnapshot(Net.snapshot(root.peers), root.livePeerSnapshot)
  }
  readonly property bool dirty: root.monitorsDirty || root.peersDirty
  readonly property var overlappingPeers: { root.revision; return Net.overlappingNames(root.localRects(), root.peers) }
  readonly property var detachedPeers: { root.revision; return Net.detachedNames(root.localRects(), root.peers) }
  readonly property var warnings: {
    root.revision
    var out = []
    var bad = Model.overlappingNames(root.monitors).concat(root.overlappingPeers)
    if (bad.length) out.push(strings.t("warn.overlap").arg(bad.join(", ")))
    var far = Model.detachedMonitors(Model.layoutMonitors(root.monitors))
    var lost = far.map(function(m) { return m.name }).concat(root.detachedPeers)
    if (lost.length) out.push(strings.t("warn.detached").arg(lost.join(", ")))
    return out
  }

  function changed() { root.revision++ }

  // This PC's screens as plain rectangles in logical pixels.
  function localRects() {
    return Model.layoutMonitors(root.monitors).map(function(m) {
      return { name: m.name, x: m.x, y: m.y, width: Model.logicalW(m), height: Model.logicalH(m) }
    })
  }

  // The screens go back to 0,0 and the network PCs move with them.
  function normalize() {
    var d = Model.normalize(root.monitors)
    Net.shift(root.peers, d[0], d[1])
  }

  function takeSnapshot() { return { m: Model.snapshot(root.monitors), p: Net.snapshot(root.peers) } }
  function restoreSnapshot(s) { Model.restore(root.monitors, s.m); Net.restore(root.peers, s.p) }

  // ------------------------------------------------------------------ theme

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color muted: Color.muted
  property string fontFamily: Style.font.family

  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  // One hue per screen and per PC, rotated from the theme accent so they stay
  // on palette. PCs come after the screens.
  function tileColor(index) {
    var a = root.accent
    var hue = a.hslHue < 0 ? 0.6 : a.hslHue
    return Qt.hsla((hue + index * 0.13) % 1, Math.max(a.hslSaturation, 0.35), Math.min(Math.max(a.hslLightness, 0.45), 0.65), 1)
  }
  function monitorColor(name) {
    var names = root.monitors.map(function(m) { return m.name }).sort()
    return root.tileColor(Math.max(0, names.indexOf(name)))
  }
  function peerColor(name) {
    var names = root.peers.map(function(p) { return p.name }).sort()
    return root.tileColor(root.monitors.length + Math.max(0, names.indexOf(name)))
  }

  // ------------------------------------------------------------- open/close

  function open(payloadJson) {
    root.opened = true
    root.reload()
  }

  function close() {
    if (!root.opened) return
    if (revertTimer.running) root.finishTry(false)
    root.identifying = false
    root.adding = false
    root.confirmRemove = ""
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.selfId)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // --------------------------------------------------------------- loading

  function reload() {
    root.undoStack = []
    root.redoStack = []
    root.undoDepth = 0
    root.redoDepth = 0
    root.configReadable = false
    root.livePeerSnapshot = ({})
    root.peers = []
    configFile.reload()
    mickeyFile.reload()
    readMonitors.running = true
    root.probe()
  }

  FileView {
    id: configFile
    path: root.configPath
    printErrors: false
    atomicWrites: false   // write in place: Hyprland watches the file for auto-reload
    onLoaded: { root.configText = text(); root.configReadable = true }
    onLoadFailed: function(err) {
      root.configText = ""
      root.configReadable = err === FileViewError.FileNotFound
    }
    onSaved: reloadProc.running = true
    onSaveFailed: function(err) { root.statusText = strings.t("status.writeFailed") }
  }

  Process {
    id: readMonitors
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var keep = root.selected ? root.selected.name : ""
          root.monitors = Model.buildMonitors(data, root.configText)
          root.liveSnapshot = Model.snapshot(root.monitors)
          var idx = root.monitors.findIndex(function(m) { return m.name === keep })
          if (idx < 0) idx = Math.max(0, root.monitors.findIndex(function(m) { return m.focused }))
          root.selectedIndex = idx
          root.changed()
        } catch (e) {
          root.statusText = strings.t("status.readFailed").arg(String(e))
        }
      }
    }
  }

  // ------------------------------------------------------- network PCs: read

  // Mickey rewrites config.toml when a PC is paired or another PC arranges the
  // group, so the file is watched; positions being edited here are kept.
  FileView {
    id: mickeyFile
    path: root.mickeyConfigPath
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.mickeyConfigText = text(); root.mickeyConfigReadable = true; root.rebuildPeers() }
    onLoadFailed: function(err) {
      root.mickeyConfigText = ""
      root.mickeyConfigReadable = err === FileViewError.FileNotFound
      root.rebuildPeers()
    }
    onSaved: root.afterPeersSaved()
    onSaveFailed: function(err) { root.statusText = strings.t("status.mickeyWriteFailed") }
  }

  function rebuildPeers() {
    var fresh = Net.keepMonitors(Net.buildPeers(root.mickeyConfigText, root.peersRaw), root.peers)
    if (root.peersDirty) {
      // keep what is being edited
      var mine = Net.snapshot(root.peers)
      Net.restore(fresh, mine)
    }
    var saved = Net.snapshot(Net.buildPeers(root.mickeyConfigText, ""))
    root.peers = fresh
    root.livePeerSnapshot = saved
    if (root.selectedPeer !== "" && !fresh.some(function(p) { return p.name === root.selectedPeer }))
      root.selectedPeer = ""
    root.changed()
  }

  Process {
    id: probeProc
    command: ["sh", "-c", root.pathPrefix
      + 'command -v mickey >/dev/null 2>&1 || { echo "@missing"; exit 0; }; '
      + 'echo "@version $(mickey --version 2>/dev/null | head -n 1)"; '
      + 'if s=$(mickey status 2>/dev/null); then echo "@status"; echo "$s"; echo "@peers"; mickey peers 2>/dev/null; '
      + 'else echo "@stopped"; fi']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.readProbe(text)
    }
  }

  function probe() { if (!probeProc.running) probeProc.running = true }

  function readProbe(text) {
    var section = "", status = "", peersText = "", state = "stopped", version = ""
    String(text).split("\n").forEach(function(line) {
      if (line.indexOf("@") === 0) {
        section = line.split(" ")[0]
        if (section === "@missing") state = "missing"
        else if (section === "@status") state = "running"
        else if (section === "@version") version = Net.cleanText(line.slice(9).replace(/^mickey\s*/i, ""), 24)
        return
      }
      if (section === "@status") status += line + "\n"
      else if (section === "@peers") peersText += line + "\n"
    })
    root.mickeyState = state
    root.mickeyVersion = version
    root.focusPeer = Net.parseStatus(status).focus
    if (peersText !== root.peersRaw) {
      root.peersRaw = peersText
      root.rebuildPeers()
    } else {
      root.changed()
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: {
      root.probe()
      if (root.adding && root.mickeyState === "running") root.mickey(["discover", "--lines"], function(ok, out) {
        if (ok) root.discovered = Net.parseDiscover(out)
      })
    }
  }

  // ---------------------------------------------------- network PCs: commands

  // One `mickey` command at a time, in order.
  property var mickeyQueue: []
  Process {
    id: mickeyProc
    property var onDone: null
    stdout: StdioCollector { id: mickeyOut; waitForEnd: true }
    stderr: StdioCollector { id: mickeyErr; waitForEnd: true }
    onExited: function(code) {
      var cb = mickeyProc.onDone
      mickeyProc.onDone = null
      var out = (mickeyOut.text + "\n" + mickeyErr.text).trim()
      if (cb) cb(code === 0 && out.indexOf("error:") !== 0, out)
      root.pumpMickey()
    }
  }

  function mickey(args, done) {
    root.mickeyQueue.push({ args: args, done: done || null })
    root.pumpMickey()
  }

  function pumpMickey() {
    if (mickeyProc.running || !root.mickeyQueue.length) return
    var job = root.mickeyQueue.shift()
    mickeyProc.onDone = job.done
    mickeyProc.command = ["sh", "-c", root.pathPrefix + 'exec mickey "$@"', "sh"].concat(job.args)
    mickeyProc.running = true
  }

  function terminal(command) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", command])
  }

  function installMickey() {
    root.terminal("'" + root.pluginDir + "/bin/omakvm' install")
    root.statusText = strings.t("status.installing")
  }

  function startMickey() {
    root.mickey(["start"], function(ok, out) {
      root.statusText = ok ? strings.t("status.started") : strings.t("status.mickeyError").arg(Net.cleanText(out, 160))
      root.probe()
    })
  }

  function goTo(name) {
    root.mickey(name === "" ? ["home"] : ["go", name], function(ok, out) {
      if (!ok) root.statusText = strings.t("status.mickeyError").arg(Net.cleanText(out, 160))
      root.probe()
    })
  }

  function connectTo(address, name) {
    address = Net.normalizeAddress(address)
    name = String(name || "").trim()
    if (!address) { root.statusText = strings.t("status.badAddress"); return }
    if (!Net.validName(name)) { root.statusText = strings.t("status.badName"); return }
    root.statusText = strings.t("status.pairing").arg(name)
    root.mickey(["connect", address, name], function(ok, out) {
      root.statusText = ok ? strings.t("status.pairingAsked").arg(name) : strings.t("status.mickeyError").arg(Net.cleanText(out, 160))
      mickeyFile.reload()
      root.probe()
    })
  }

  function letPair() {
    root.mickey(["pairing"], function(ok, out) {
      root.statusText = ok ? strings.t("status.pairingOpen") : strings.t("status.mickeyError").arg(Net.cleanText(out, 160))
    })
  }

  function addOverSsh(target) {
    target = String(target || "").trim()
    if (!Net.validSshTarget(target)) { root.statusText = strings.t("status.badSsh"); return }
    root.terminal("'" + root.pluginDir + "/bin/omakvm' add-ssh " + target)
    root.statusText = strings.t("status.sshStarted").arg(target)
  }

  // Removing a PC: its [[peer]] table goes, its key stops being trusted, and
  // Mickey starts again (it reads the list of PCs only when it starts).
  Process {
    id: forgetProc
    property string peerName: ""
    onExited: function(code) {
      root.statusText = strings.t("status.removed").arg(forgetProc.peerName)
      root.probe()
    }
  }

  function removePeer(name) {
    var p = root.peers.find(function(o) { return o.name === name })
    var text = Net.removePeer(root.mickeyConfigText, name)
    root.confirmRemove = ""
    if (!p || text === null) return
    root.undoStack = []; root.redoStack = []; root.undoDepth = 0; root.redoDepth = 0
    root.afterSave = function() {
      forgetProc.peerName = name
      var key = /^[0-9a-f]{64}$/.test(p.key) ? p.key : ""
      forgetProc.command = ["sh", "-c", root.pathPrefix
        + 'key="$1"; f="${XDG_DATA_HOME:-$HOME/.local/share}/mickey/trusted_peers"; '
        + 'if [ -n "$key" ] && [ -f "$f" ]; then t=$(mktemp "$f.XXXXXX") && { grep -v "^$key" "$f" > "$t"; '
        + 'chmod --reference="$f" "$t"; mv "$t" "$f"; }; fi; '
        + 'systemctl --user restart mickey.service 2>/dev/null || { mickey quit; mickey start; }; exit 0',
        "sh", key]
      forgetProc.running = true
    }
    root.selectedPeer = ""
    root.peers = root.peers.filter(function(o) { return o.name !== name })
    root.changed()
    root.writeMickeyConfig(Net.setPositions(text, root.peers))
  }

  // ------------------------------------------------------ network PCs: save

  property var afterSave: null

  Process {
    id: mickeyBackupProc
    property string newText: ""
    command: ["sh", "-c", 'f="$1"; mkdir -p "$(dirname "$f")" || exit 1; [ -f "$f" ] || exit 0; '
              + 'cp -p "$f" "$f.bak.$(date +%Y%m%d%H%M%S)" || exit 1; '
              + 'ls -1 "$f".bak.* 2>/dev/null | head -n -10 | xargs -r rm -f; exit 0', "sh", root.mickeyConfigPath]
    onExited: function(code) {
      if (code !== 0) { root.statusText = strings.t("status.backupFailed"); return }
      mickeyFile.setText(mickeyBackupProc.newText)
    }
  }

  function writeMickeyConfig(text) {
    if (!root.mickeyConfigReadable) { root.statusText = strings.t("status.mickeyUnreadable"); return }
    mickeyBackupProc.newText = text
    mickeyBackupProc.running = true
  }

  function savePeers() {
    root.pendingPeerSave = false
    root.afterSave = function() {
      if (root.mickeyState !== "running") { root.statusText = strings.t("status.savedNotRunning"); return }
      root.mickey(["arranged"], function(ok, out) {
        root.statusText = ok ? strings.t("status.savedAll") : strings.t("status.mickeyError").arg(Net.cleanText(out, 160))
      })
    }
    root.writeMickeyConfig(Net.setPositions(root.mickeyConfigText, root.peers))
  }

  function afterPeersSaved() {
    root.mickeyConfigText = mickeyBackupProc.newText
    root.livePeerSnapshot = Net.snapshot(root.peers)
    root.changed()
    var cb = root.afterSave
    root.afterSave = null
    if (cb) cb()
  }

  // -------------------------------------------------------------- applying

  // Runs `hyprctl eval` once per Lua line and stops at the first answer that
  // isn't "ok" (with the Lua config, `hyprctl keyword` no longer works).
  Process {
    id: evalProc
    property var onDone: null
    stdout: StdioCollector { id: evalOut; waitForEnd: true }
    onExited: function(code) {
      var cb = evalProc.onDone
      evalProc.onDone = null
      if (cb) cb(code === 0, evalOut.text.trim())
    }
  }

  function evalLines(monitors, done) {
    var lines = Model.applyOrder(monitors).map(function(m) { return Model.luaInline(m, true) })
    evalProc.onDone = done
    evalProc.command = ["sh", "-c",
      'for l in "$@"; do out=$(hyprctl eval "$l" 2>&1); [ "$out" = ok ] || { echo "$out"; exit 1; }; done',
      "sh"].concat(lines)
    evalProc.running = true
  }

  property var previousMonitors: []
  property int countdown: 0

  // Read the live state right before applying, so a rollback restores what
  // Hyprland really had (not what was loaded when the panel opened).
  Process {
    id: liveProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.previousMonitors = Model.buildMonitors(JSON.parse(text), root.configText)
        } catch (e) {
          root.statusText = strings.t("status.readFailed").arg(String(e))
          return
        }
        root.evalLines(root.monitors, function(ok, out) {
          if (!ok) {
            root.statusText = strings.t("status.notApplied").arg(out)
            root.evalLines(root.previousMonitors, null)
            return
          }
          root.countdown = root.revertSeconds
          revertTimer.start()
        })
      }
    }
  }

  function tryLayout() {
    if (evalProc.running || liveProc.running || revertTimer.running) return
    root.normalize()
    root.changed()
    liveProc.running = true
  }

  function finishTry(keep) {
    revertTimer.stop()
    root.countdown = 0
    if (keep) {
      root.liveSnapshot = Model.snapshot(root.monitors)
      root.statusText = strings.t("status.applied")
      root.changed()
    } else {
      root.evalLines(root.previousMonitors, null)
      root.statusText = strings.t("status.restored")
    }
  }

  Timer {
    id: revertTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.countdown--
      if (root.countdown <= 0) root.finishTry(false)
    }
  }

  // ---------------------------------------------------------------- saving

  Process {
    id: backupProc
    property string newText: ""
    // A failed copy must fail the whole command; trimming old backups must not.
    // Names carry the timestamp: `ls -t` is useless here since cp -p keeps the source's mtime.
    command: ["sh", "-c", 'f="$1"; [ -f "$f" ] || exit 0; cp -p "$f" "$f.bak.$(date +%Y%m%d%H%M%S)" || exit 1; '
              + 'ls -1 "$f".bak.* 2>/dev/null | head -n -10 | xargs -r rm -f; exit 0', "sh", root.configPath]
    onExited: function(code) {
      if (code !== 0) { root.statusText = strings.t("status.backupFailed"); return }
      configFile.setText(backupProc.newText)
    }
  }

  Process {
    id: reloadProc
    command: ["sh", "-c", "hyprctl reload >/dev/null && hyprctl -j configerrors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var errors = []
        try { errors = JSON.parse(text).filter(function(e) { return e && e.trim() }) } catch (e) {}
        if (errors.length) {
          root.statusText = strings.t("status.savedErrors").arg(errors.join(" · "))
          root.pendingPeerSave = false
        } else {
          root.configText = backupProc.newText
          root.liveSnapshot = Model.snapshot(root.monitors)
          root.statusText = strings.t("status.saved")
          root.changed()
          if (root.pendingPeerSave) root.savePeers()
        }
      }
    }
  }

  function save() {
    if (backupProc.running || reloadProc.running || mickeyBackupProc.running) return
    if (!root.configReadable) {
      root.statusText = strings.t("status.unreadable")
      return
    }
    root.normalize()
    root.peers.forEach(function(p) { Net.attach(root.localRects(), root.peers, p) })
    root.changed()
    root.pendingPeerSave = root.peersDirty
    var text = Model.updateConfigText(root.configText, root.monitors)
    // Only the network PCs moved: leave monitors.lua and Hyprland alone.
    if (text === root.configText && !root.monitorsDirty) {
      if (root.pendingPeerSave) root.savePeers()
      else root.statusText = strings.t("status.nothing")
      return
    }
    backupProc.newText = text
    backupProc.running = true
  }

  // ---------------------------------------------------------------- editing

  function select(i) { root.selectedPeer = ""; root.confirmRemove = ""; root.selectedIndex = i; root.changed() }
  function selectPeer(name) { root.confirmRemove = ""; root.selectedPeer = name; root.changed() }

  // Call before every mutation of the layout.
  function pushUndo() {
    root.undoStack.push(root.takeSnapshot())
    if (root.undoStack.length > root.undoLimit) root.undoStack.shift()
    root.redoStack = []
    root.undoDepth = root.undoStack.length
    root.redoDepth = 0
  }

  function undo() {
    if (!root.undoStack.length) return
    root.redoStack.push(root.takeSnapshot())
    root.restoreSnapshot(root.undoStack.pop())
    root.undoDepth = root.undoStack.length
    root.redoDepth = root.redoStack.length
    root.changed()
  }

  function redo() {
    if (!root.redoStack.length) return
    root.undoStack.push(root.takeSnapshot())
    root.restoreSnapshot(root.redoStack.pop())
    root.undoDepth = root.undoStack.length
    root.redoDepth = root.redoStack.length
    root.changed()
  }

  function setPosition(axis, value) {
    var p = root.peer
    if (p) {
      if (!p.placed) return
      var b = Net.box(p)
      var want = value - (axis === "x" ? b.x : b.y)
      if (p[axis] === want) return
      root.pushUndo()
      p[axis] = want
      Net.attach(root.localRects(), root.peers, p)
      root.changed()
      return
    }
    var m = root.selected
    if (!m || !Model.inLayout(m) || m[axis] === value) return
    root.pushUndo()
    m[axis] = value
    root.normalize()
    root.changed()
  }

  function nudge(dx, dy) {
    var p = root.peer
    if (p) {
      if (!p.placed) return
      root.pushUndo()
      p.x += dx
      p.y += dy
      root.changed()
      return
    }
    var m = root.selected
    if (!m || !Model.inLayout(m)) return
    root.pushUndo()
    m.x += dx
    m.y += dy
    root.normalize()
    root.changed()
  }

  // Tab goes through the screens in layout order, then the network PCs.
  function selectNext(step) {
    var order = Model.displayOrder(root.monitors).map(function(i) { return ["m", i] })
      .concat(root.peers.map(function(p) { return ["p", p.name] }))
    var n = order.length
    if (!n) return
    var at = order.findIndex(function(o) {
      return root.selectedPeer !== "" ? (o[0] === "p" && o[1] === root.selectedPeer)
                                      : (o[0] === "m" && o[1] === root.selectedIndex)
    })
    var next = order[(at + step + n) % n]
    if (next[0] === "p") root.selectPeer(next[1])
    else root.select(next[1])
  }

  function handleKey(e) {
    if (root.adding) { e.accepted = false; return }
    var ctrl = e.modifiers & Qt.ControlModifier
    var shift = e.modifiers & Qt.ShiftModifier
    var step = shift ? 1 : 10
    e.accepted = true
    if (ctrl && e.key === Qt.Key_Z) { shift ? root.redo() : root.undo() }
    else if (ctrl && e.key === Qt.Key_Y) root.redo()
    else if (e.key === Qt.Key_Left) root.nudge(-step, 0)
    else if (e.key === Qt.Key_Right) root.nudge(step, 0)
    else if (e.key === Qt.Key_Up) root.nudge(0, -step)
    else if (e.key === Qt.Key_Down) root.nudge(0, step)
    else if (e.key === Qt.Key_Tab) root.selectNext(1)
    else if (e.key === Qt.Key_Backtab) root.selectNext(-1)
    else e.accepted = false
  }

  function identify() {
    root.identifying = true
    identifyTimer.restart()
  }

  // A size change keeps the neighbours attached, network PCs included.
  function changeSize(m, mutate) {
    var moves = Model.changeGeometry(root.monitors, m, mutate, Net.rects(root.peers))
    root.peers.forEach(function(p) {
      var d = moves[p.name]
      if (d) { p.x = Math.round(p.x + d[0]); p.y = Math.round(p.y + d[1]) }
    })
  }

  function setMode(value) {
    var m = root.selected
    root.pushUndo()
    var md = m.modes[parseInt(value, 10)]
    root.changeSize(m, function() {
      m.width = md[0]; m.height = md[1]; m.refresh = md[2]
      m.scale = Model.nearest(Model.validScales(md[0], md[1]), m.scale)
    })
    root.changed()
  }

  function setScale(value) {
    var m = root.selected
    root.pushUndo()
    root.changeSize(m, function() { m.scale = parseFloat(value) })
    root.changed()
  }

  function setTransform(value) {
    var m = root.selected
    root.pushUndo()
    root.changeSize(m, function() { m.transform = parseInt(value, 10) })
    root.changed()
  }

  function setEnabled(on) {
    var m = root.selected
    if (!on && Model.layoutMonitors(root.monitors).filter(function(o) { return o !== m }).length === 0) {
      root.statusText = strings.t("status.oneScreen")
      return
    }
    root.pushUndo()
    m.disabled = !on
    if (m.disabled) root.monitors.forEach(function(o) { if (o.mirror === m.name) o.mirror = "" })
    root.normalize()
    root.changed()
  }

  function setMirror(value) {
    var m = root.selected
    root.pushUndo()
    m.mirror = value === "-" ? "" : value
    if (m.mirror) root.monitors.forEach(function(o) { if (o.mirror === m.name) o.mirror = "" })
    root.normalize()
    root.changed()
  }

  function setVrr(value) { root.pushUndo(); root.selected.vrr = parseInt(value, 10); root.changed() }

  // On the layout: the cursor crosses to the PC at the shared edge. Off: the
  // PC stays paired and is reached with Mickey's hotkeys only.
  function setPlaced(on) {
    var p = root.peer
    if (!p || p.placed === on) return
    root.pushUndo()
    if (on) Net.place(root.localRects(), root.peers, p)
    else p.placed = false
    root.changed()
  }

  function fix() {
    var before = root.takeSnapshot()
    var did = Model.autoArrange(root.monitors)
    // PCs that cover something or touch nothing go against the nearest edge.
    root.peers.forEach(function(p) {
      if (Net.attach(root.localRects(), root.peers, p)) did = true
    })
    if (!did) return
    root.undoStack.push(before)
    if (root.undoStack.length > root.undoLimit) root.undoStack.shift()
    root.redoStack = []
    root.undoDepth = root.undoStack.length
    root.redoDepth = 0
    root.changed()
  }

  function peerSummary(p) {
    if (!p) return ""
    if (p.state === "reinstalled") return strings.t("peer.reinstalled")
    var where = !p.placed ? strings.t("peer.hotkeysOnly")
      : root.detachedPeers.indexOf(p.name) >= 0 ? strings.t("peer.noEdge")
      : strings.t("peer.side." + (Net.side(root.localRects(), p) || "near"))
    return (p.online ? strings.t("peer.online") : strings.t("peer.offline")) + " · " + where
  }

  // ---------------------------------------------------------------- identify

  Timer {
    id: identifyTimer
    interval: 3000
    onTriggered: root.identifying = false
  }

  // One click-through card per screen, centred, showing that output's name.
  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      id: overlay
      required property var modelData
      readonly property var mon: {
        root.revision
        return root.monitors.find(function(m) { return m.name === overlay.modelData.name }) || null
      }
      screen: modelData
      visible: root.identifying
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omakvm-identify"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Rectangle {
        anchors.centerIn: parent
        width: idCol.implicitWidth + Style.space(64)
        height: idCol.implicitHeight + Style.space(48)
        radius: Style.cornerRadius + Style.space(6)
        color: root.background
        border.width: Style.space(3)
        border.color: root.monitorColor(overlay.modelData.name)
        Column {
          id: idCol
          anchors.centerIn: parent
          spacing: Style.space(4)
          PlainText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: overlay.modelData.name
            font.pixelSize: Style.space(56)
            font.bold: true
          }
          PlainText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !!overlay.mon
            text: overlay.mon ? overlay.mon.width + "×" + overlay.mon.height + " · " + Model.fmtRefresh(overlay.mon.refresh) + " Hz" : ""
            color: root.muted
            font.pixelSize: Style.font.title
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ window

  // A layer-shell overlay instead of a toplevel: Hyprland would tile a normal
  // window, while this floats centred over everything without any window rule.
  PanelWindow {
    id: win
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omakvm"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.35)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1180), parent.width - Style.space(48))
      height: Math.min(Style.space(720), parent.height - Style.space(48))
      radius: Style.cornerRadius + Style.space(6)
      color: root.background
      border.width: Style.space(1)
      border.color: root.border

      MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }

      Item {
        id: keys
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        focus: true
        Keys.onEscapePressed: {
          if (root.adding) { root.adding = false; keys.forceActiveFocus() }
          else root.close()
        }
        Keys.onPressed: function(e) { root.handleKey(e) }

        // ---- header
        Row {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.md
          height: Math.max(titleCol.implicitHeight, saveBtn.implicitHeight)

          Column {
            id: titleCol
            width: parent.width - actions.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            PlainText {
              text: strings.t("title")
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            PlainText {
              width: parent.width
              elide: Text.ElideRight
              text: {
                root.revision
                var n = Model.layoutMonitors(root.monitors).length
                var s = strings.tn("header.screens", n).arg(n)
                if (root.peers.length) {
                  var on = root.peers.filter(function(p) { return p.online }).length
                  s += " · " + strings.tn("header.pcs", root.peers.length).arg(root.peers.length).arg(on)
                }
                if (root.focusPeer !== "") s += " · " + strings.t("header.keyboardOn").arg(root.focusPeer)
                return s + " · " + (root.dirty ? strings.t("header.unsaved") : strings.t("header.current"))
              }
              color: root.muted
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: actions
            spacing: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            Button { text: strings.t("action.undo"); bordered: true; enabled: root.undoDepth > 0; onClicked: root.undo() }
            Button { text: strings.t("action.redo"); bordered: true; enabled: root.redoDepth > 0; onClicked: root.redo() }
            Button { text: strings.t("action.identify"); bordered: true; selected: root.identifying; onClicked: root.identify() }
            Button { text: strings.t("action.reload"); bordered: true; onClicked: root.reload() }
            Button {
              text: root.snapEnabled ? strings.t("action.snapOn") : strings.t("action.snapOff")
              bordered: true
              selected: root.snapEnabled
              onClicked: root.snapEnabled = !root.snapEnabled
            }
            Button { text: strings.t("action.try"); bordered: true; tooltipText: strings.t("action.tryTip"); onClicked: root.tryLayout() }
            Button { id: saveBtn; text: strings.t("action.save"); bordered: true; active: true; onClicked: root.save() }
          }
        }

        // ---- canvas
        Rectangle {
          id: canvas
          anchors.top: header.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.bottom: statusLine.top
          anchors.bottomMargin: Style.spacing.md
          width: parent.width - sidebar.width - Style.spacing.xl
          radius: Style.cornerRadius
          color: root.mix(root.background, root.foreground, 0.03)
          border.color: root.mix(root.background, root.foreground, 0.12)
          clip: true

          // view transform, frozen while dragging so the layout doesn't rescale under the cursor
          property bool frozen: false
          property real zoom: 0.1
          property real ox: 0
          property real oy: 0
          property real px: 0
          property real py: 0
          property var guides: []

          function fit() {
            if (canvas.frozen) return
            var lay = root.localRects().concat(Net.rects(root.peers))
            if (!lay.length || canvas.width <= 0) return
            var minX = Math.min.apply(null, lay.map(function(m) { return m.x }))
            var minY = Math.min.apply(null, lay.map(function(m) { return m.y }))
            var bw = Math.max(Math.max.apply(null, lay.map(function(m) { return m.x + m.width })) - minX, 1)
            var bh = Math.max(Math.max.apply(null, lay.map(function(m) { return m.y + m.height })) - minY, 1)
            var pad = Style.space(48)
            canvas.zoom = Math.max(0.01, Math.min(0.5, Math.min((canvas.width - 2 * pad) / bw, (canvas.height - 2 * pad) / bh)))
            canvas.ox = minX
            canvas.oy = minY
            canvas.px = (canvas.width - bw * canvas.zoom) / 2
            canvas.py = (canvas.height - bh * canvas.zoom) / 2
          }
          onWidthChanged: fit()
          onHeightChanged: fit()
          Connections {
            target: root
            function onRevisionChanged() { canvas.fit() }
          }

          // this PC's screens
          Repeater {
            model: {
              root.revision
              return root.monitors.map(function(m, i) { return i })
            }

            delegate: Rectangle {
              id: tile
              required property int modelData
              readonly property var mon: { root.revision; return root.monitors[modelData] }
              readonly property bool isSelected: root.selectedPeer === "" && modelData === root.selectedIndex
              readonly property color tint: root.monitorColor(mon ? mon.name : "")
              readonly property bool overlapping: { root.revision; return Model.overlappingNames(root.monitors).indexOf(mon.name) >= 0 }

              visible: !!mon && Model.inLayout(mon)
              x: { root.revision; canvas.zoom; return mon ? (mon.x - canvas.ox) * canvas.zoom + canvas.px : 0 }
              y: { root.revision; canvas.zoom; return mon ? (mon.y - canvas.oy) * canvas.zoom + canvas.py : 0 }
              width: { root.revision; return mon ? Model.logicalW(mon) * canvas.zoom : 0 }
              height: { root.revision; return mon ? Model.logicalH(mon) * canvas.zoom : 0 }
              z: isSelected ? 2 : 1
              radius: Math.min(Style.cornerRadius + Style.space(6), width / 8, height / 8)
              color: root.mix(root.background, tint, isSelected ? 0.34 : (dragArea.containsMouse ? 0.24 : 0.16))
              border.width: isSelected ? Style.space(3) : Style.space(1)
              border.color: overlapping ? root.urgent : tint

              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                spacing: Style.space(2)
                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: tile.mon ? tile.mon.name : ""
                  font.pixelSize: Math.max(Style.font.caption, Math.min(Style.font.display, tile.height * 0.12))
                  font.bold: true
                }
                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  visible: tile.height > Style.space(70)
                  text: tile.mon ? tile.mon.width + "×" + tile.mon.height + " · " + Model.fmtRefresh(tile.mon.refresh)
                                   + " Hz\n" + strings.t("tile.scale").arg(Model.scaleLabel(tile.mon.scale)) + " · "
                                   + Math.round(Model.logicalW(tile.mon)) + "×" + Math.round(Model.logicalH(tile.mon)) : ""
                  color: root.mix(root.background, root.foreground, 0.75)
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real startX: 0
                property real startY: 0
                property real pressX: 0
                property real pressY: 0
                property var sticky: [null, null]
                property bool undoPushed: false

                onPressed: function(mouse) {
                  keys.forceActiveFocus()
                  root.select(tile.modelData)
                  var p = mapToItem(canvas, mouse.x, mouse.y)
                  pressX = p.x; pressY = p.y
                  startX = tile.mon.x; startY = tile.mon.y
                  sticky = [null, null]
                  undoPushed = false
                  canvas.frozen = true
                }
                onPositionChanged: function(mouse) {
                  if (!pressed) return
                  var p = mapToItem(canvas, mouse.x, mouse.y)
                  var nx = startX + (p.x - pressX) / canvas.zoom
                  var ny = startY + (p.y - pressY) / canvas.zoom
                  if (root.snapEnabled && !(mouse.modifiers & Qt.ShiftModifier)) {
                    var others = Model.layoutMonitors(root.monitors).filter(function(o) { return o !== tile.mon })
                    var r = Model.snapPosition(tile.mon, nx, ny, others, root.snapPx / canvas.zoom, sticky)
                    nx = r.x; ny = r.y; sticky = r.sticky
                    canvas.guides = r.guides
                  } else {
                    canvas.guides = []
                  }
                  nx = Math.round(nx); ny = Math.round(ny)
                  if (nx === tile.mon.x && ny === tile.mon.y) return
                  if (!undoPushed) { root.pushUndo(); undoPushed = true }
                  tile.mon.x = nx; tile.mon.y = ny
                  root.changed()
                }
                onReleased: {
                  canvas.frozen = false
                  canvas.guides = []
                  root.normalize()
                  root.changed()
                }
              }
            }
          }

          // network PCs: one tile per PC, its own screens drawn inside
          Repeater {
            model: {
              root.revision
              return root.peers.filter(function(p) { return p.placed }).map(function(p) { return p.name })
            }

            delegate: Item {
              id: pc
              required property string modelData
              readonly property var peer: { root.revision; return root.peers.find(function(p) { return p.name === pc.modelData }) || null }
              readonly property var box: { root.revision; return peer ? Net.box(peer) : { x: 0, y: 0, w: 1, h: 1 } }
              readonly property bool isSelected: root.selectedPeer === modelData
              readonly property color tint: root.peerColor(modelData)
              readonly property bool overlapping: root.overlappingPeers.indexOf(modelData) >= 0
              readonly property bool hasFocus: root.focusPeer === modelData

              x: { root.revision; canvas.zoom; return peer ? (peer.x + box.x - canvas.ox) * canvas.zoom + canvas.px : 0 }
              y: { root.revision; canvas.zoom; return peer ? (peer.y + box.y - canvas.oy) * canvas.zoom + canvas.py : 0 }
              width: box.w * canvas.zoom
              height: box.h * canvas.zoom
              z: isSelected ? 2 : 1
              opacity: peer && peer.online ? 1 : 0.6

              // The PC's screens, or one placeholder while it has never been seen.
              Repeater {
                model: {
                  root.revision
                  var mons = pc.peer && pc.peer.monitors.length ? pc.peer.monitors
                    : [{ x: 0, y: 0, width: pc.box.w, height: pc.box.h }]
                  return mons
                }
                delegate: Rectangle {
                  required property var modelData
                  x: (modelData.x - pc.box.x) * canvas.zoom
                  y: (modelData.y - pc.box.y) * canvas.zoom
                  width: modelData.width * canvas.zoom
                  height: modelData.height * canvas.zoom
                  radius: Math.min(Style.cornerRadius + Style.space(6), width / 8, height / 8)
                  color: root.mix(root.background, pc.tint, pc.isSelected ? 0.3 : (pcArea.containsMouse ? 0.2 : 0.1))
                  border.width: pc.isSelected ? Style.space(3) : Style.space(1)
                  border.color: pc.overlapping ? root.urgent : pc.tint
                }
              }

              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                spacing: Style.space(2)
                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: pc.modelData
                  font.pixelSize: Math.max(Style.font.caption, Math.min(Style.font.display, pc.height * 0.12))
                  font.bold: true
                }
                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  visible: pc.height > Style.space(70)
                  text: !pc.peer ? "" : strings.t("tile.network") + " · "
                        + (pc.hasFocus ? strings.t("tile.keyboardHere")
                           : pc.peer.online ? strings.t("peer.online") : strings.t("peer.offline"))
                  color: pc.hasFocus ? root.accent : root.mix(root.background, root.foreground, 0.75)
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: pcArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real startX: 0
                property real startY: 0
                property real pressX: 0
                property real pressY: 0
                property var sticky: [null, null]
                property bool undoPushed: false

                onPressed: function(mouse) {
                  keys.forceActiveFocus()
                  root.selectPeer(pc.modelData)
                  var p = mapToItem(canvas, mouse.x, mouse.y)
                  pressX = p.x; pressY = p.y
                  startX = pc.peer.x + pc.box.x; startY = pc.peer.y + pc.box.y
                  sticky = [null, null]
                  undoPushed = false
                  canvas.frozen = true
                }
                onPositionChanged: function(mouse) {
                  if (!pressed || !pc.peer) return
                  var p = mapToItem(canvas, mouse.x, mouse.y)
                  var nx = startX + (p.x - pressX) / canvas.zoom
                  var ny = startY + (p.y - pressY) / canvas.zoom
                  if (root.snapEnabled && !(mouse.modifiers & Qt.ShiftModifier)) {
                    var others = Model.layoutMonitors(root.monitors)
                      .concat(Net.rects(root.peers).filter(function(r) { return r.name !== pc.modelData }))
                    var r = Model.snapPosition(Net.rect(pc.peer), nx, ny, others, root.snapPx / canvas.zoom, sticky)
                    nx = r.x; ny = r.y; sticky = r.sticky
                    canvas.guides = r.guides
                  } else {
                    canvas.guides = []
                  }
                  nx = Math.round(nx) - pc.box.x; ny = Math.round(ny) - pc.box.y
                  if (nx === pc.peer.x && ny === pc.peer.y) return
                  if (!undoPushed) { root.pushUndo(); undoPushed = true }
                  pc.peer.x = nx; pc.peer.y = ny
                  root.changed()
                }
                onReleased: {
                  canvas.frozen = false
                  canvas.guides = []
                  // A PC that touches nothing cannot be reached with the cursor.
                  if (pc.peer && Net.attach(root.localRects(), root.peers, pc.peer))
                    root.statusText = strings.t("status.attached").arg(pc.modelData)
                  root.changed()
                }
              }
            }
          }

          // snap guides
          Repeater {
            model: canvas.guides
            delegate: Rectangle {
              required property var modelData
              readonly property bool vertical: modelData[0] === "v"
              z: 3
              color: root.accent
              opacity: 0.8
              x: vertical ? (modelData[1] - canvas.ox) * canvas.zoom + canvas.px : 0
              y: vertical ? 0 : (modelData[1] - canvas.oy) * canvas.zoom + canvas.py
              width: vertical ? Style.space(1) : canvas.width
              height: vertical ? canvas.height : Style.space(1)
            }
          }

          // warnings float over the canvas so they never shift the layout
          Rectangle {
            z: 4
            visible: root.warnings.length > 0 && !canvas.frozen && !root.adding
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Style.spacing.lg
            width: Math.min(warnRow.implicitWidth + Style.spacing.xl * 2, parent.width - Style.spacing.xl * 2)
            height: warnRow.implicitHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: root.background
            border.color: root.urgent
            Row {
              id: warnRow
              anchors.centerIn: parent
              spacing: Style.spacing.lg
              PlainText {
                anchors.verticalCenter: parent.verticalCenter
                text: "⚠  " + root.warnings.join(" · ")
              }
              Button { text: strings.t("action.fix"); bordered: true; onClicked: root.fix() }
            }
          }

          // confirm a tried layout; without an answer it rolls back on its own
          Rectangle {
            z: 5
            visible: revertTimer.running
            anchors.centerIn: parent
            width: confirmCol.implicitWidth + Style.spacing.xxl * 2
            height: confirmCol.implicitHeight + Style.spacing.xxl * 2
            radius: Style.cornerRadius
            color: root.background
            border.color: root.accent
            Column {
              id: confirmCol
              anchors.centerIn: parent
              spacing: Style.spacing.lg
              PlainText {
                text: strings.t("try.keep")
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              PlainText {
                text: strings.t("try.reverting").arg(root.countdown)
                color: root.muted
              }
              Row {
                spacing: Style.spacing.md
                Button { text: strings.t("try.revert"); bordered: true; onClicked: root.finishTry(false) }
                Button { text: strings.t("try.keepButton"); bordered: true; active: true; onClicked: root.finishTry(true) }
              }
            }
          }

          // add a PC: the ones Mickey hears on this network, one by address,
          // or one reached over ssh (no screen to compare codes on)
          Rectangle {
            id: addCard
            z: 6
            visible: root.adding
            anchors.centerIn: parent
            width: Math.min(Style.space(560), parent.width - Style.spacing.xl * 2)
            height: Math.min(addCol.implicitHeight + Style.spacing.xl * 2, parent.height - Style.spacing.xl * 2)
            radius: Style.cornerRadius
            color: root.background
            border.color: root.accent
            clip: true

            MouseArea { anchors.fill: parent }

            Column {
              id: addCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.spacing.xl
              spacing: Style.spacing.md

              PlainText {
                text: strings.t("add.title")
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: root.muted
                font.pixelSize: Style.font.caption
                text: root.mickeyState !== "running" ? strings.t("add.needsMickey")
                    : root.discovered.length ? strings.t("add.found") : strings.t("add.searching")
              }

              Repeater {
                model: root.adding ? root.discovered.filter(function(d) {
                  root.revision
                  return !root.peers.some(function(p) { return p.address === d.address })
                }).slice(0, 6) : []
                delegate: Row {
                  id: found
                  required property var modelData
                  width: addCol.width
                  spacing: Style.spacing.md
                  Column {
                    width: parent.width - connectBtn.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    PlainText { width: parent.width; elide: Text.ElideRight; text: found.modelData.name }
                    PlainText {
                      width: parent.width
                      elide: Text.ElideRight
                      color: root.muted
                      font.pixelSize: Style.font.caption
                      text: found.modelData.address + (found.modelData.fingerprint ? "  ·  " + found.modelData.fingerprint : "")
                    }
                  }
                  Button {
                    id: connectBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: strings.t("add.connect")
                    bordered: true
                    onClicked: root.connectTo(found.modelData.address, found.modelData.name)
                  }
                }
              }

              PanelSeparator { width: parent.width }

              PlainText { text: strings.t("add.byAddress"); font.bold: true }
              Row {
                width: parent.width
                spacing: Style.spacing.sm
                TextField {
                  id: addrField
                  width: (parent.width - byAddrBtn.width - parent.spacing * 2) * 0.55
                  placeholderText: "192.168.0.10"
                  foreground: root.foreground
                  accent: root.accent
                  onAccepted: root.connectTo(addrField.text, nameField.text)
                }
                TextField {
                  id: nameField
                  width: (parent.width - byAddrBtn.width - parent.spacing * 2) * 0.45
                  placeholderText: strings.t("add.name")
                  foreground: root.foreground
                  accent: root.accent
                  onAccepted: root.connectTo(addrField.text, nameField.text)
                }
                Button {
                  id: byAddrBtn
                  text: strings.t("add.connect")
                  bordered: true
                  onClicked: root.connectTo(addrField.text, nameField.text)
                }
              }
              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: root.muted
                font.pixelSize: Style.font.caption
                text: strings.t("add.byAddressHint")
              }

              PanelSeparator { width: parent.width }

              PlainText { text: strings.t("add.overSsh"); font.bold: true }
              Row {
                width: parent.width
                spacing: Style.spacing.sm
                TextField {
                  id: sshField
                  width: parent.width - sshBtn.width - parent.spacing
                  placeholderText: "user@192.168.0.20"
                  foreground: root.foreground
                  accent: root.accent
                  onAccepted: root.addOverSsh(sshField.text)
                }
                Button {
                  id: sshBtn
                  text: strings.t("add.setUp")
                  bordered: true
                  onClicked: root.addOverSsh(sshField.text)
                }
              }
              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: root.muted
                font.pixelSize: Style.font.caption
                text: strings.t("add.overSshHint")
              }

              Row {
                spacing: Style.spacing.sm
                Button {
                  text: strings.t("add.letPair")
                  bordered: true
                  enabled: root.mickeyState === "running"
                  tooltipText: strings.t("add.letPairTip")
                  onClicked: root.letPair()
                }
                Button {
                  text: strings.t("add.close")
                  bordered: true
                  active: true
                  onClicked: { root.adding = false; keys.forceActiveFocus() }
                }
              }
            }
          }
        }

        // ---- sidebar
        Flickable {
          id: sidebar
          anchors.top: canvas.top
          anchors.bottom: canvas.bottom
          anchors.right: parent.right
          width: Style.space(320)
          contentWidth: width
          contentHeight: sideCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: sideCol
            width: sidebar.width
            spacing: Style.spacing.md

            PlainText {
              text: strings.t("side.screens")
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Repeater {
              model: { root.revision; return Model.displayOrder(root.monitors) }
              delegate: Rectangle {
                id: row
                required property int modelData
                readonly property var mon: { root.revision; return root.monitors[modelData] }
                width: sideCol.width
                height: rowCol.implicitHeight + Style.spacing.md * 2
                radius: Style.cornerRadius
                color: (root.selectedPeer === "" && modelData === root.selectedIndex) ? Style.selectedFill
                       : (rowArea.containsMouse ? Style.hoverFill : "transparent")
                Rectangle {
                  id: dot
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(10); height: width; radius: width / 2
                  color: root.monitorColor(row.mon ? row.mon.name : "")
                }
                Column {
                  id: rowCol
                  anchors.left: dot.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  PlainText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.mon ? row.mon.name + "   " + (row.mon.disabled ? strings.t("side.off")
                                    : row.mon.mirror ? strings.t("side.mirrors").arg(row.mon.mirror)
                                    : row.mon.width + "×" + row.mon.height + " · " + Model.scaleLabel(row.mon.scale) + "×") : ""
                  }
                  PlainText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.mon ? Model.subtitle(row.mon) : ""
                    color: root.muted
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; onClicked: { keys.forceActiveFocus(); root.select(row.modelData) } }
              }
            }

            // ---- network PCs
            Row {
              width: sideCol.width
              spacing: Style.spacing.md
              PlainText {
                width: parent.width - addBtn.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("side.pcs")
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Button {
                id: addBtn
                text: strings.t("side.add")
                bordered: true
                visible: root.mickeyState !== "missing" && root.mickeyState !== "unknown"
                onClicked: { root.discovered = []; root.adding = true }
              }
            }

            Column {
              width: sideCol.width
              spacing: Style.spacing.sm
              visible: root.mickeyState === "missing" || root.mickeyState === "stopped"
              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: root.muted
                font.pixelSize: Style.font.caption
                text: root.mickeyState === "missing" ? strings.t("side.mickeyMissing") : strings.t("side.mickeyStopped")
              }
              Button {
                text: root.mickeyState === "missing" ? strings.t("side.install") : strings.t("side.start")
                bordered: true
                active: true
                onClicked: root.mickeyState === "missing" ? root.installMickey() : root.startMickey()
              }
            }

            PlainText {
              width: sideCol.width
              wrapMode: Text.WordWrap
              visible: root.mickeyState === "running" && root.peers.length === 0
              color: root.muted
              font.pixelSize: Style.font.caption
              text: strings.t("side.noPcs")
            }

            Repeater {
              model: { root.revision; return root.peers.map(function(p) { return p.name }) }
              delegate: Rectangle {
                id: pcRow
                required property string modelData
                readonly property var peer: { root.revision; return root.peers.find(function(p) { return p.name === pcRow.modelData }) || null }
                width: sideCol.width
                height: pcRowCol.implicitHeight + Style.spacing.md * 2
                radius: Style.cornerRadius
                color: root.selectedPeer === modelData ? Style.selectedFill
                       : (pcRowArea.containsMouse ? Style.hoverFill : "transparent")
                Rectangle {
                  id: pcDot
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(10); height: width; radius: width / 2
                  color: pcRow.peer && pcRow.peer.online ? root.peerColor(pcRow.modelData) : "transparent"
                  border.width: Style.space(2)
                  border.color: root.peerColor(pcRow.modelData)
                }
                Column {
                  id: pcRowCol
                  anchors.left: pcDot.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  PlainText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pcRow.modelData + (root.focusPeer === pcRow.modelData ? "   ⌨" : "")
                  }
                  PlainText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.peerSummary(pcRow.peer)
                    color: root.muted
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea { id: pcRowArea; anchors.fill: parent; hoverEnabled: true; onClicked: { keys.forceActiveFocus(); root.selectPeer(pcRow.modelData) } }
              }
            }

            Item { width: 1; height: Style.spacing.sm }

            // ---- the selected network PC
            PlainText {
              visible: !!root.peer
              width: sideCol.width
              elide: Text.ElideRight
              text: root.peer ? root.peer.name : ""
              font.pixelSize: Style.font.title
              font.bold: true
            }

            PlainText {
              visible: !!root.peer
              width: sideCol.width
              wrapMode: Text.WrapAnywhere
              color: root.muted
              font.pixelSize: Style.font.caption
              text: root.peer ? root.peer.address + (root.peer.version ? "  ·  Mickey " + root.peer.version : "")
                                + (root.peer.monitors.length ? "  ·  " + root.peer.monitors.map(function(m) { return m.width + "×" + m.height }).join(" + ") : "")
                              : ""
            }

            Row {
              visible: !!root.peer
              spacing: Style.spacing.md
              ToggleSwitch {
                checked: { root.revision; return root.peer ? root.peer.placed : false }
                onToggled: root.setPlaced(!checked)
              }
              PlainText {
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("peer.onLayout")
              }
            }

            PlainText {
              visible: !!root.peer
              width: sideCol.width
              wrapMode: Text.WordWrap
              color: root.muted
              font.pixelSize: Style.font.caption
              text: {
                root.revision
                if (!root.peer) return ""
                if (!root.peer.placed) return strings.t("peer.hotkeysHint")
                if (root.detachedPeers.indexOf(root.peer.name) >= 0) return strings.t("peer.noEdgeHint")
                return strings.t("peer.edgeHint")
              }
            }

            Row {
              visible: !!root.peer
              spacing: Style.spacing.md
              readonly property real fieldW: (sideCol.width - spacing) / 2
              NumberField {
                label: "X"
                fieldWidth: parent.fieldW
                enabled: !!root.peer && root.peer.placed
                from: -64000; to: 64000
                value: { root.revision; return root.peer ? Math.round(root.peer.x + Net.box(root.peer).x) : 0 }
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.setPosition("x", v) }
              }
              NumberField {
                label: "Y"
                fieldWidth: parent.fieldW
                enabled: !!root.peer && root.peer.placed
                from: -64000; to: 64000
                value: { root.revision; return root.peer ? Math.round(root.peer.y + Net.box(root.peer).y) : 0 }
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.setPosition("y", v) }
              }
            }

            Row {
              visible: !!root.peer && root.confirmRemove === ""
              spacing: Style.spacing.sm
              Button {
                text: root.peer && root.focusPeer === root.peer.name ? strings.t("peer.bringBack") : strings.t("peer.sendKeyboard")
                bordered: true
                enabled: !!root.peer && root.mickeyState === "running" && (root.peer.online || root.focusPeer === root.peer.name)
                tooltipText: strings.t("peer.sendKeyboardTip")
                onClicked: root.goTo(root.focusPeer === root.peer.name ? "" : root.peer.name)
              }
              Button {
                text: strings.t("peer.remove")
                bordered: true
                onClicked: root.confirmRemove = root.peer ? root.peer.name : ""
              }
            }

            Column {
              visible: !!root.peer && root.confirmRemove !== "" && root.confirmRemove === root.selectedPeer
              width: sideCol.width
              spacing: Style.spacing.sm
              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                text: strings.t("peer.removeAsk")
              }
              Row {
                spacing: Style.spacing.sm
                Button { text: strings.t("peer.removeNo"); bordered: true; onClicked: root.confirmRemove = "" }
                Button { text: strings.t("peer.removeYes"); bordered: true; active: true; onClicked: root.removePeer(root.confirmRemove) }
              }
            }

            // ---- the selected screen
            PlainText {
              visible: !!root.selected
              text: root.selected ? root.selected.name : ""
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              visible: !!root.selected
              spacing: Style.spacing.md
              ToggleSwitch {
                checked: { root.revision; return root.selected ? !root.selected.disabled : false }
                onToggled: root.setEnabled(!checked)
              }
              PlainText {
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("screen.enabled")
              }
            }

            Dropdown {
              width: sideCol.width
              visible: !!root.selected
              enabled: !!root.selected && Model.inLayout(root.selected)
              label: strings.t("screen.resolution")
              value: { root.revision; return root.selected ? String(Model.modeIndex(root.selected)) : "" }
              options: {
                root.revision
                if (!root.selected) return []
                return root.selected.modes.map(function(md, i) {
                  return { label: md[0] + "×" + md[1] + " @ " + Model.fmtRefresh(md[2]) + " Hz", value: String(i) }
                })
              }
              onChanged: function(v) { root.setMode(v) }
            }

            Dropdown {
              width: sideCol.width
              visible: !!root.selected
              enabled: !!root.selected && Model.inLayout(root.selected)
              label: strings.t("screen.scale")
              value: { root.revision; return root.selected ? String(Model.nearest(Model.scalesFor(root.selected), root.selected.scale)) : "" }
              options: {
                root.revision
                var m = root.selected
                if (!m) return []
                var lw = Model.isRotated(m) ? m.height : m.width
                var lh = Model.isRotated(m) ? m.width : m.height
                return Model.scalesFor(m).map(function(s) {
                  return { label: Model.scaleLabel(s) + "× · " + Math.round(lw / s) + "×" + Math.round(lh / s), value: String(s) }
                })
              }
              onChanged: function(v) { root.setScale(v) }
            }

            Dropdown {
              width: sideCol.width
              visible: !!root.selected
              enabled: !!root.selected && Model.inLayout(root.selected)
              label: strings.t("screen.rotation")
              value: { root.revision; return root.selected ? String(root.selected.transform) : "" }
              options: Model.TRANSFORMS.map(function(t, i) { return { label: strings.t("screen.transform." + i), value: String(i) } })
              onChanged: function(v) { root.setTransform(v) }
            }

            Dropdown {
              width: sideCol.width
              visible: !!root.selected
              enabled: !!root.selected && !root.selected.disabled
              label: strings.t("screen.mirror")
              value: { root.revision; return root.selected && root.selected.mirror ? root.selected.mirror : "-" }
              options: {
                root.revision
                var m = root.selected
                if (!m) return []
                return [{ label: strings.t("screen.mirrorNo"), value: "-" }].concat(root.monitors.filter(function(o) {
                  return o !== m && !o.disabled && !o.mirror
                }).map(function(o) { return { label: o.name, value: o.name } }))
              }
              onChanged: function(v) { root.setMirror(v) }
            }

            Dropdown {
              width: sideCol.width
              visible: !!root.selected
              enabled: !!root.selected && !root.selected.disabled
              label: "VRR"
              value: { root.revision; return root.selected ? String(root.selected.vrr) : "" }
              options: Model.VRR_MODES.map(function(t, i) { return { label: strings.t("screen.vrr." + i), value: String(i) } })
              onChanged: function(v) { root.setVrr(v) }
            }

            Row {
              visible: !!root.selected
              spacing: Style.spacing.md
              readonly property real fieldW: (sideCol.width - spacing) / 2
              NumberField {
                label: "X"
                fieldWidth: parent.fieldW
                enabled: !!root.selected && Model.inLayout(root.selected)
                from: -32000; to: 32000
                value: { root.revision; return root.selected ? Math.round(root.selected.x) : 0 }
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.setPosition("x", v) }
              }
              NumberField {
                label: "Y"
                fieldWidth: parent.fieldW
                enabled: !!root.selected && Model.inLayout(root.selected)
                from: -32000; to: 32000
                value: { root.revision; return root.selected ? Math.round(root.selected.y) : 0 }
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.setPosition("y", v) }
              }
            }
          }
        }

        // ---- status line
        PlainText {
          id: statusLine
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          elide: Text.ElideRight
          text: root.statusText || strings.t("status.hint")
          color: root.muted
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
