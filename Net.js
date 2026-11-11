.pragma library

// Pure logic for the network PCs: what Mickey prints, Mickey's config.toml,
// and where each PC's desktop sits next to this one. No QML types in here, so
// test/net.test.js can run it under plain node.
//
// A network PC ("peer") is a plain object:
//   { name, address, key, hotkey, online, state, version,
//     monitors: [{ x, y, width, height }], placed, x, y }
// monitors are in the peer's own logical pixels. x/y is where the peer's point
// 0,0 sits in this PC's desktop (Mickey's `position`); placed=false means no
// position: the peer is reached with the hotkeys only.

var DEFAULT_PORT = 4242
var PLACEHOLDER = [1920, 1080]

// ------------------------------------------------------------ mickey output

// "2560x1080+0+0;1920x1080+246+-1080"
function parseMonitors(text) {
  var out = []
  String(text || "").split(";").forEach(function(part) {
    var m = /^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$/.exec(part.trim())
    if (!m) return
    var mon = { x: parseInt(m[3], 10), y: parseInt(m[4], 10), width: parseInt(m[1], 10), height: parseInt(m[2], 10) }
    if (mon.width > 0 && mon.height > 0 && mon.width <= 32768 && mon.height <= 32768) out.push(mon)
  })
  return out
}

// `mickey peers`: "this\t<monitors>" and "peer\t<state>\t<version>\t<name>\t<monitors>".
function parsePeers(text) {
  var res = { thisPc: [], peers: [] }
  String(text || "").split("\n").forEach(function(line) {
    if (!line) return
    var f = line.split("\t")
    if (f[0] === "this") {
      res.thisPc = parseMonitors(f[1])
    } else if (f[0] === "peer" && f.length >= 4) {
      res.peers.push({
        name: f[3],
        state: f[1],
        online: f[1] === "online",
        version: f[2] === "-" ? "" : cleanText(f[2], 24),
        monitors: parseMonitors(f[4])
      })
    }
  })
  return res
}

// `mickey discover --lines`: "name\taddress\tfingerprint".
function parseDiscover(text) {
  var out = []
  String(text || "").split("\n").forEach(function(line) {
    var f = line.split("\t")
    if (f.length < 2 || !validAddress(f[1])) return
    out.push({ name: cleanText(f[0], 64), address: f[1], fingerprint: cleanText(f[2] || "", 64) })
  })
  return out.slice(0, 64)
}

// `mickey status`: "focus: <name>", "in control: ...", then "<name>: online".
function parseStatus(text) {
  var res = { running: false, focus: "", local: true }
  String(text || "").split("\n").forEach(function(line) {
    var m = /^focus: (.*)$/.exec(line)
    if (m) {
      res.running = true
      res.local = m[1] === "this PC"
      res.focus = res.local ? "" : m[1]
    }
  })
  return res
}

// One line of `mickey status --waybar`.
function parseWaybar(line) {
  try {
    var o = JSON.parse(line)
    var cls = String(o.class || "off")
    var text = cleanText(String(o.text || ""), 96)
    return { state: cls === "remote" ? "remote" : cls === "local" ? "local" : "off",
             focus: cls === "remote" ? text.replace(/ · \d+\/\d+$/, "") : "",
             text: text }
  } catch (e) {
    return { state: "off", focus: "", text: "" }
  }
}

// Text from the network ends up on screen: keep it short and on one line.
function cleanText(s, max) {
  return String(s || "").replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, max || 64)
}

// For text handed to a shell component whose Text format this plugin cannot
// set (a bar tooltip): nothing in it can start a tag or an entity.
function noMarkup(s) {
  return cleanText(s, 96).replace(/[<>&]/g, " ")
}

function validAddress(s) {
  var m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}):(\d{1,5})$/.exec(String(s || ""))
  if (!m) return false
  for (var i = 1; i <= 4; i++) if (parseInt(m[i], 10) > 255) return false
  var port = parseInt(m[5], 10)
  return port > 0 && port < 65536
}

// "192.168.0.5" or "192.168.0.5:4242" -> "192.168.0.5:4242"; "" when it is neither.
function normalizeAddress(s) {
  s = String(s || "").trim()
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(s)) s += ":" + DEFAULT_PORT
  return validAddress(s) ? s : ""
}

// A name Mickey accepts and that is safe as one command argument.
function validName(s) {
  s = String(s || "")
  return s.length > 0 && s.length <= 64 && !/[\u0000-\u001f\u007f"\\]/.test(s) && s.trim() === s
}

// An ssh destination: user@host, host, with letters, digits, dots and dashes.
function validSshTarget(s) {
  return /^([A-Za-z0-9_][A-Za-z0-9_.-]{0,31}@)?[A-Za-z0-9]([A-Za-z0-9.-]{0,252}[A-Za-z0-9])?$/.test(String(s || ""))
}

// --------------------------------------------------------------- config.toml

function tomlString(s) {
  return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

// The value of one `key = value` line: a string, an array of integers, a
// boolean or null when it is something else.
function tomlValue(raw) {
  raw = raw.trim()
  var m
  if (raw[0] === '"') {
    var out = "", i = 1
    while (i < raw.length && raw[i] !== '"') {
      if (raw[i] === "\\" && i + 1 < raw.length) {
        var c = raw[i + 1]
        if (c === "n") out += "\n"
        else if (c === "t") out += "\t"
        else if (c === "u" && /^[0-9A-Fa-f]{4}$/.test(raw.substr(i + 2, 4))) {
          out += String.fromCharCode(parseInt(raw.substr(i + 2, 4), 16)); i += 4
        } else out += c
        i += 2
      } else {
        out += raw[i]; i++
      }
    }
    return i < raw.length ? out : null
  }
  if (raw[0] === "'") {
    var end = raw.indexOf("'", 1)
    return end > 0 ? raw.slice(1, end) : null
  }
  if ((m = /^\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]/.exec(raw))) return [parseInt(m[1], 10), parseInt(m[2], 10)]
  if ((m = /^(true|false)\b/.exec(raw))) return m[1] === "true"
  return null
}

function keyOf(line) {
  var m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line)
  return m ? [m[1], m[2]] : null
}

function header(line) {
  var t = line.trim()
  return t[0] === "[" ? t : ""
}

// The [[peer]] tables of config.toml, in file order.
function parseConfigPeers(text) {
  var peers = [], cur = null
  String(text || "").split("\n").forEach(function(line) {
    var h = header(line)
    if (h) {
      cur = null
      if (h.indexOf("[[peer]]") === 0) {
        cur = { name: "", address: "", key: "", hotkey: "", position: null }
        peers.push(cur)
      }
      return
    }
    if (!cur) return
    var kv = keyOf(line)
    if (!kv) return
    var v = tomlValue(kv[1])
    if (kv[0] === "name" && typeof v === "string") cur.name = v
    else if (kv[0] === "address" && typeof v === "string") cur.address = v
    else if (kv[0] === "key" && typeof v === "string") cur.key = v
    else if (kv[0] === "hotkey" && typeof v === "string") cur.hotkey = v
    else if (kv[0] === "position" && v instanceof Array) cur.position = v
  })
  return peers.filter(function(p) { return p.name !== "" })
}

// `name` under [this_pc]; "" when unset (Mickey then uses the host name).
function thisPcName(text) {
  var inside = false, name = ""
  String(text || "").split("\n").forEach(function(line) {
    var h = header(line)
    if (h) { inside = h.indexOf("[this_pc]") === 0; return }
    var kv = inside ? keyOf(line) : null
    if (kv && kv[0] === "name") {
      var v = tomlValue(kv[1])
      if (typeof v === "string") name = v
    }
  })
  return name
}

// Line ranges [first, end) of the [[peer]] table named `name`, or null.
function peerRange(lines, name) {
  var start = -1, found = false
  for (var i = 0; i <= lines.length; i++) {
    var h = i < lines.length ? header(lines[i]) : "[end]"
    if (h) {
      if (found) return [start, i]
      start = h.indexOf("[[peer]]") === 0 ? i : -1
      continue
    }
    if (start >= 0) {
      var kv = keyOf(lines[i])
      if (kv && kv[0] === "name" && tomlValue(kv[1]) === name) found = true
    }
  }
  return null
}

function joinLines(lines) {
  return lines.join("\n").replace(/\n+$/, "") + "\n"
}

// Set (position = [x, y]) or drop (position = null) one peer's position,
// leaving every other line of the file as it is. Returns null when no peer
// has that name.
function setPosition(text, name, position) {
  var lines = String(text || "").split("\n")
  var range = peerRange(lines, name)
  if (!range) return null
  var wanted = position ? "position = [" + Math.round(position[0]) + ", " + Math.round(position[1]) + "]" : null
  var at = -1, nameAt = range[0]
  for (var i = range[0] + 1; i < range[1]; i++) {
    var kv = keyOf(lines[i])
    if (!kv) continue
    if (kv[0] === "position") at = i
    if (kv[0] === "name") nameAt = i
  }
  if (at >= 0) {
    if (wanted) lines[at] = wanted
    else lines.splice(at, 1)
  } else if (wanted) {
    lines.splice(nameAt + 1, 0, wanted)
  }
  return joinLines(lines)
}

// Apply every peer's placement in one pass.
function setPositions(text, peers) {
  peers.forEach(function(p) {
    var next = setPosition(text, p.name, p.placed ? [p.x, p.y] : null)
    if (next !== null) text = next
  })
  return text
}

// Take one [[peer]] table out. Returns null when no peer has that name.
function removePeer(text, name) {
  var lines = String(text || "").split("\n")
  var range = peerRange(lines, name)
  if (!range) return null
  var first = range[0], end = range[1]
  // The blank lines that set the table apart go with it.
  while (end > first && lines[end - 1].trim() === "") end--
  while (first > 0 && lines[first - 1].trim() === "") first--
  lines.splice(first, end - first)
  if (first > 0 && first < lines.length && lines[first].trim() !== "") lines.splice(first, 0, "")
  return joinLines(lines)
}

// ------------------------------------------------------------------ peers

// config.toml says which PCs exist and where; `mickey peers` says which are
// online and what their monitors are.
function buildPeers(configText, peersText) {
  var live = {}
  parsePeers(peersText).peers.forEach(function(p) { live[p.name] = p })
  return parseConfigPeers(configText).map(function(c) {
    var l = live[c.name] || {}
    return {
      name: c.name,
      address: c.address,
      key: c.key,
      hotkey: c.hotkey,
      online: !!l.online,
      state: l.state || "offline",
      version: l.version || "",
      monitors: l.monitors || [],
      placed: !!c.position,
      x: c.position ? c.position[0] : 0,
      y: c.position ? c.position[1] : 0
    }
  })
}

// The monitors keep the ones last seen while a peer is offline, so its tile
// does not shrink to the placeholder between two reads.
function keepMonitors(peers, previous) {
  var old = {}
  ;(previous || []).forEach(function(p) { old[p.name] = p })
  peers.forEach(function(p) {
    if (!p.monitors.length && old[p.name] && old[p.name].monitors.length) p.monitors = old[p.name].monitors
  })
  return peers
}

// Bounding box of a peer's monitors in its own space.
function box(peer) {
  var mons = peer.monitors || []
  if (!mons.length) return { x: 0, y: 0, w: PLACEHOLDER[0], h: PLACEHOLDER[1] }
  var x0 = Math.min.apply(null, mons.map(function(m) { return m.x }))
  var y0 = Math.min.apply(null, mons.map(function(m) { return m.y }))
  var x1 = Math.max.apply(null, mons.map(function(m) { return m.x + m.width }))
  var y1 = Math.max.apply(null, mons.map(function(m) { return m.y + m.height }))
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

// The peer as one rectangle of this PC's desktop, shaped like a Model.js
// monitor so the same snapping and overlap code takes it.
function rect(peer) {
  var b = box(peer)
  return { name: peer.name, peer: true, x: peer.x + b.x, y: peer.y + b.y, width: b.w, height: b.h,
           scale: 1, transform: 0, disabled: false, mirror: "" }
}

function placed(peers) { return (peers || []).filter(function(p) { return p.placed }) }
function rects(peers) { return placed(peers).map(rect) }

function state(p) { return [p.placed, Math.round(p.x), Math.round(p.y)] }

function snapshot(peers) {
  var snap = {}
  ;(peers || []).forEach(function(p) { snap[p.name] = state(p) })
  return snap
}

function restore(peers, snap) {
  ;(peers || []).forEach(function(p) {
    var st = snap[p.name]
    if (!st) return
    p.placed = st[0]; p.x = st[1]; p.y = st[2]
  })
}

function sameSnapshot(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

function shift(peers, dx, dy) {
  placed(peers).forEach(function(p) { p.x = Math.round(p.x + dx); p.y = Math.round(p.y + dy) })
}

function intersects(a, b) {
  return a.x < b.x + b.width - 0.5 && b.x < a.x + a.width - 0.5 &&
         a.y < b.y + b.height - 0.5 && b.y < a.y + a.height - 0.5
}

function touching(a, b) {
  var v = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y)
  var h = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)
  var side = (Math.abs(a.x + a.width - b.x) < 1 || Math.abs(b.x + b.width - a.x) < 1) && v > 0
  var stacked = (Math.abs(a.y + a.height - b.y) < 1 || Math.abs(b.y + b.height - a.y) < 1) && h > 0
  return side || stacked
}

// `local` is this PC's screens as rectangles { x, y, width, height } in
// logical pixels.
function overlappingNames(local, peers) {
  var rs = rects(peers), names = {}
  rs.forEach(function(r, i) {
    local.forEach(function(l) { if (intersects(r, l)) names[r.name] = true })
    for (var j = i + 1; j < rs.length; j++)
      if (intersects(r, rs[j])) { names[r.name] = true; names[rs[j].name] = true }
  })
  return Object.keys(names).sort()
}

// Placed peers the cursor cannot reach: they touch neither this PC's screens
// nor a peer that does.
function detachedNames(local, peers) {
  var left = rects(peers), reached = local.slice(), grew = true
  while (grew) {
    grew = false
    for (var i = left.length - 1; i >= 0; i--) {
      if (reached.some(function(r) { return touching(left[i], r) })) {
        reached.push(left.splice(i, 1)[0]); grew = true
      }
    }
  }
  return left.map(function(r) { return r.name }).sort()
}

// Put a peer to the right of everything, its top level with the layout's top.
function place(local, peers, peer) {
  var others = local.concat(rects(peers).filter(function(r) { return r.name !== peer.name }))
  var b = box(peer)
  var right = others.length ? Math.max.apply(null, others.map(function(r) { return r.x + r.width })) : 0
  var top = local.length ? Math.min.apply(null, local.map(function(r) { return r.y })) : 0
  peer.placed = true
  peer.x = Math.round(right - b.x)
  peer.y = Math.round(top - b.y)
}

// Which side of this PC's screens the peer sits on, for the sidebar:
// "left", "right", "above", "below" or "".
function side(local, peer) {
  if (!peer.placed || !local.length) return ""
  var r = rect(peer)
  for (var i = 0; i < local.length; i++) {
    var l = local[i]
    if (!touching(r, l)) continue
    if (Math.abs(l.x + l.width - r.x) < 1) return "right"
    if (Math.abs(r.x + r.width - l.x) < 1) return "left"
    if (Math.abs(l.y + l.height - r.y) < 1) return "below"
    if (Math.abs(r.y + r.height - l.y) < 1) return "above"
  }
  return ""
}
