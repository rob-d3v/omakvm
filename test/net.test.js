#!/usr/bin/env node
'use strict'

// Tests for Net.js and the peer-aware parts of Model.js without a QML host:
//   node test/net.test.js

const fs = require('fs')
const path = require('path')
const vm = require('vm')

function load(file) {
  const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8').replace(/^\.pragma library\s*/, '')
  const ctx = {}
  vm.createContext(ctx)
  vm.runInContext(source, ctx, { filename: file })
  return ctx
}
const N = load('Net.js')
const M = load('Model.js')

let checks = 0
let failures = 0
function check(label, actual, expected) {
  checks++
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    failures++
    console.error(`FAIL ${label}:\n  expected ${e}\n  got      ${a}`)
  }
}

// --- what mickey prints
check('monitors', N.parseMonitors('2560x1080+0+0;1920x1080+246+-1080'),
  [{ x: 0, y: 0, width: 2560, height: 1080 }, { x: 246, y: -1080, width: 1920, height: 1080 }])
check('monitors: junk is dropped', N.parseMonitors('axb+0+0;;99999x10+0+0;10x10+1'), [])

const peersText = 'this\t1536x864+0+0\n' +
  'peer\tonline\t0.4.5\tWindows A\t2560x1080+0+0;1920x1080+246+-1080\n' +
  'peer\toffline\t-\tKiosk\n' +
  'peer\treinstalled\t0.4.4\tOld\t800x480+0+0\n'
const parsed = N.parsePeers(peersText)
check('peers: this', parsed.thisPc, [{ x: 0, y: 0, width: 1536, height: 864 }])
check('peers: names', parsed.peers.map(p => [p.name, p.state, p.online, p.version, p.monitors.length]),
  [['Windows A', 'online', true, '0.4.5', 2], ['Kiosk', 'offline', false, '', 0], ['Old', 'reinstalled', false, '0.4.4', 1]])

check('discover', N.parseDiscover('Desk\t192.168.0.7:4242\tABCD-EFGH\nbad\tnot-an-address\tX\n<img src=x>\t10.0.0.2:4242\t\n'),
  [{ name: 'Desk', address: '192.168.0.7:4242', fingerprint: 'ABCD-EFGH' },
   { name: '<img src=x>', address: '10.0.0.2:4242', fingerprint: '' }])
check('status: remote', N.parseStatus('focus: Kiosk\nin control: this PC\nKiosk: online\n'), { running: true, focus: 'Kiosk', local: false })
check('status: local', N.parseStatus('focus: this PC\nin control: this PC\n'), { running: true, focus: '', local: true })
check('status: not running', N.parseStatus('mickey: cannot reach the running Mickey'), { running: false, focus: '', local: true })
check('waybar: remote', N.parseWaybar('{"text":"Kiosk · 1/2","tooltip":"x","class":"remote"}'), { state: 'remote', focus: 'Kiosk', text: 'Kiosk · 1/2' })
check('waybar: off', N.parseWaybar('{"text":"Mickey off","tooltip":"x","class":"off"}').state, 'off')
check('waybar: junk', N.parseWaybar('nope').state, 'off')

check('no markup for tooltips', N.noMarkup('<img src="https://x.invalid/t">&amp;'), ' img src="https://x.invalid/t"  amp;')
check('address: bare ip', N.normalizeAddress(' 192.168.0.51 '), '192.168.0.51:4242')
check('address: with port', N.normalizeAddress('192.168.0.51:5000'), '192.168.0.51:5000')
check('address: bad', [N.normalizeAddress('300.1.1.1'), N.normalizeAddress('host:22'), N.normalizeAddress('1.2.3.4:0')], ['', '', ''])
check('name', [N.validName('Wall display'), N.validName(''), N.validName('a"b'), N.validName(' x'), N.validName('a\tb')],
  [true, false, false, false, false])
check('ssh target', ['pi@192.168.0.20', 'central', 'a@b.local', 'a b', '-oProxyCommand=x', 'u@h;rm', ''].map(N.validSshTarget),
  [true, true, true, false, false, false, false])

// --- config.toml
const config = `# my PCs
[[peer]]
name = "Windows A"
address = "192.168.0.7:4242"
position = [2560, 0]
key = "${'ab'.repeat(32)}"

[[peer]]
name = 'Kiosk'   # bench
address = "192.168.0.20:4242"

[touchpad]
speed = 16

[this_pc]
name = "desk"
controls_others = true
`
check('config peers', N.parseConfigPeers(config).map(p => [p.name, p.address, p.position, p.key.length]),
  [['Windows A', '192.168.0.7:4242', [2560, 0], 64], ['Kiosk', '192.168.0.20:4242', null, 0]])
check('this pc name', N.thisPcName(config), 'desk')
check('this pc name: unset', N.thisPcName('[this_pc]\ncontrolled = true\n'), '')
check('toml escapes', N.parseConfigPeers('[[peer]]\nname = "a \\"b\\" \\\\ c"\naddress = "1.2.3.4:1"\n')[0].name, 'a "b" \\ c')
check('toml string round trip', N.tomlValue(N.tomlString('a "b" \\ c')), 'a "b" \\ c')

let moved = N.setPosition(config, 'Windows A', [-1920, 40])
check('set position: replaced in place', N.parseConfigPeers(moved)[0].position, [-1920, 40])
check('set position: one line only', moved.split('position =').length, 2)
check('set position: rest untouched', moved.replace('position = [-1920, 40]', 'position = [2560, 0]'), config)

let added = N.setPosition(config, 'Kiosk', [0, 1080])
check('set position: added after the name', added.split('\n').slice(8, 10), ["name = 'Kiosk'   # bench", 'position = [0, 1080]'])
check('set position: other peer kept', N.parseConfigPeers(added)[0].position, [2560, 0])
check('drop position', N.parseConfigPeers(N.setPosition(config, 'Windows A', null))[0].position, null)
check('drop position: nothing to drop', N.setPosition(config, 'Kiosk', null), config)
check('set position: unknown peer', N.setPosition(config, 'Nobody', [0, 0]), null)

const removed = N.removePeer(config, 'Windows A')
check('remove peer: gone', N.parseConfigPeers(removed).map(p => p.name), ['Kiosk'])
check('remove peer: rest kept', removed, `# my PCs

[[peer]]
name = 'Kiosk'   # bench
address = "192.168.0.20:4242"

[touchpad]
speed = 16

[this_pc]
name = "desk"
controls_others = true
`)
check('remove last peer keeps sections', N.removePeer(removed, 'Kiosk'), `# my PCs

[touchpad]
speed = 16

[this_pc]
name = "desk"
controls_others = true
`)
check('remove peer: unknown', N.removePeer(config, 'Nobody'), null)

// --- peers on the desktop
const peers = N.buildPeers(config, peersText)
check('build: merged', peers.map(p => [p.name, p.online, p.placed, p.x, p.y, p.monitors.length]),
  [['Windows A', true, true, 2560, 0, 2], ['Kiosk', false, false, 0, 0, 0]])
check('box: two monitors', N.box(peers[0]), { x: 0, y: -1080, w: 2560, h: 2160 })
check('box: placeholder', N.box(peers[1]), { x: 0, y: 0, w: 1920, h: 1080 })
check('rect', [N.rect(peers[0]).x, N.rect(peers[0]).y, N.rect(peers[0]).width, N.rect(peers[0]).height], [2560, -1080, 2560, 2160])

const local = [{ x: 0, y: 0, width: 2560, height: 1080 }, { x: 2560, y: 508, width: 1280, height: 720 }]
check('overlap: Windows A sits on the laptop screen', N.overlappingNames(local, peers), ['Windows A'])
N.place(local, peers, peers[0])
check('place: right of everything, top aligned', [peers[0].x, peers[0].y], [3840, 1080])
check('place: no overlap left', N.overlappingNames(local, peers), [])
check('side', N.side(local, peers[0]), 'right')
check('detached: none', N.detachedNames(local, peers), [])
N.place(local, peers, peers[1])
check('place: second goes after the first', [peers[1].x, peers[1].y], [6400, 0])
check('detached: chain through another peer counts', N.detachedNames(local, peers), [])
peers[1].x += 500
check('detached: gap', N.detachedNames(local, peers), ['Kiosk'])
peers[1].x = -1920; peers[1].y = 0
check('side: left', N.side(local, peers[1]), 'left')

const snap = N.snapshot(peers)
peers[0].placed = false
check('snapshot differs', N.sameSnapshot(snap, N.snapshot(peers)), false)
N.restore(peers, snap)
check('restore', N.sameSnapshot(snap, N.snapshot(peers)), true)
N.shift(peers, 100, -8)
check('shift', [peers[0].x, peers[0].y, peers[1].x, peers[1].y], [3940, 1072, -1820, -8])

const kept = N.keepMonitors(N.buildPeers(config, 'this\t1x1+0+0\n'), [{ name: 'Windows A', monitors: [{ x: 0, y: 0, width: 800, height: 480 }] }])
check('keep monitors of an offline peer', kept[0].monitors.length, 1)

const saved = N.setPositions(config, [{ name: 'Windows A', placed: false, x: 0, y: 0 }, { name: 'Kiosk', placed: true, x: -1920.4, y: 12 }])
check('set positions', N.parseConfigPeers(saved).map(p => p.position), [null, [-1920, 12]])

// --- Model.js: what the network PCs need from it
const mons = [
  { name: 'A', width: 2560, height: 1080, x: 100, y: 50, scale: 1, transform: 0, disabled: false, mirror: '' },
  { name: 'B', width: 1920, height: 1080, x: 2660, y: 50, scale: 1.5, transform: 0, disabled: false, mirror: '' }
]
check('normalize says how far it moved', M.normalize(mons), [-100, -50])
check('normalize: already there', M.normalize(mons), [0, 0])
const att = [{ name: 'P', x: 3840, y: 0, width: 800, height: 480 }, { name: 'Q', x: 0, y: 1080, width: 800, height: 480 }]
const moves = M.changeGeometry(mons, mons[1], function() { mons[1].scale = 1 }, att)
check('changeGeometry: peer on the right follows, the other stays', moves, { P: [640, 0], Q: [0, 0] })

console.log(failures ? `\n${failures} of ${checks} checks failed` : `${checks} checks passed`)
process.exit(failures ? 1 : 0)
