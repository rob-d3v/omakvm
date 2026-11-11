# omakvm

One keyboard and mouse for the PCs on your network, arranged like monitors.

omakvm puts this PC's screens and your other computers on one canvas. Drag a PC
next to a screen, press **Save**, and from then on pushing the cursor across that
edge takes the keyboard and mouse to that PC; push it back and they come home. The
clipboard follows the keyboard.

Unofficial community plugin for [Omarchy](https://omarchy.org). It stands on two
projects and does none of the hard work itself:

- The screens half is [Monitor Manager](https://github.com/FabioCuccaro/omarchy_monitor_manager)
  by Fabio Cuccaro (MIT): drag and snap your monitors, resolution, scale, rotation,
  mirroring, VRR, try live with automatic rollback, save to `~/.config/hypr/monitors.lua`.
  Everything it does, this panel still does.
- The network half is [Mickey](https://github.com/EduardoMG12/mickey) by EduardoMG12
  (GPL-3.0-or-later), a separate program that carries the keyboard, mouse and clipboard
  between PCs over an encrypted link. omakvm only runs `mickey` commands and edits
  the positions in Mickey's `config.toml`. It never sees a key or the clipboard.

## What you get

- **Network PCs as tiles** beside your monitors, with the screens each PC really has.
  Drag them with the same snapping, or type exact X / Y. A PC that touches nothing
  is flagged: the cursor cannot cross to it.
- **Add PC** lists the computers running Mickey on your network. *Connect*, check
  that both screens show the same six-digit code, done.
- **Add over SSH**, for a PC with no screen to compare codes on (a board, a kiosk,
  a media box): `omakvm add-ssh` installs Mickey there and pairs the two PCs through
  the SSH connection you already trust. x86-64 and ARM64 Linux.
- **On the layout** switch per PC: off, the PC stays paired and is reached with the
  hotkeys only.
- **Send keyboard** and **Remove** per PC.
- **Bar icon**: two screens; the second fills in while your keyboard is on another PC.
  Click opens the panel, right click opens Mickey's PC switcher, middle click brings
  the keyboard home.
- English and Brazilian Portuguese, following Omarchy's language.

The way home always works, whatever the layout says: hold **Right Shift** for 3
seconds, or press **AltGr + Right Shift**.

## Requirements

- Omarchy 4 with the Quickshell shell and Hyprland ≥ 0.55 (Lua config).
- Mickey on every PC that takes part. The panel offers to install it on this one;
  on the others use [Mickey's own installers](https://github.com/EduardoMG12/mickey#install)
  (Windows, `.deb`, `.rpm`, or the tarball) or **Add over SSH**.
- `curl`, `openssl` and `tar` for the installer; `ssh` and `scp` for Add over SSH.

## Install

```bash
omarchy plugin add https://github.com/rob-d3v/omakvm --enable
```

Then click the two-screens icon in the bar. If Mickey is missing, the panel shows
**Install Mickey**, which opens a terminal and runs:

```bash
~/.config/omarchy/plugins/io.github.rob-d3v.omakvm/bin/omakvm install
```

That downloads Mickey's latest release, checks it against Mickey's release key
(the Ed25519 signature over `SHA256SUMS`), and installs it for your user the way
Mickey's own `install.sh` does. It asks for your password once, for the part that
needs root:

- a udev rule so the `input` group can create Mickey's virtual keyboard and mouse;
- adding you to the `input` group, so Mickey can read your keyboard and mouse;
- opening TCP 4242-4243 and UDP 4243-4244 in ufw or firewalld, if one is on.

Read this before you agree: **every program you run as a member of the `input` group
can read your keyboard, not only Mickey.** That is Mickey's own requirement
([its README](https://github.com/EduardoMG12/mickey#known-limits) says the same).
Install it only on your own PCs.

The group is in full effect after one restart. Until then the installer grants your
user the devices that exist now, so Mickey works right away; a keyboard or mouse
plugged in before that restart is not seen.

If you already use Monitor Manager, disable it so you do not have two icons:
`omarchy plugin disable io.github.fabiocuccaro.monitor-manager`.

## Use

| Where | What |
| --- | --- |
| Bar icon, click | Open or close the panel |
| Bar icon, right click | Mickey's switcher: one card per PC |
| Bar icon, middle click | Bring the keyboard and mouse home |
| Drag a tile | Move a screen or a PC; <kbd>Shift</kbd> turns snapping off |
| <kbd>←↑↓→</kbd> | Nudge the selected tile by 10 px (<kbd>Shift</kbd>: 1 px) |
| <kbd>Tab</kbd> / <kbd>Shift+Tab</kbd> | Next / previous screen, then the PCs |
| <kbd>Ctrl+Z</kbd>, <kbd>Ctrl+Shift+Z</kbd> | Undo, redo |
| **Try** | Apply the screens for 15 s, roll back unless you keep them |
| **Save** | Write `monitors.lua` if a screen changed, and Mickey's positions if a PC moved |
| <kbd>Esc</kbd> | Close |

From a script or a key binding:

```bash
omarchy-shell shell toggle io.github.rob-d3v.omakvm
```

Saving the PCs writes each one's `position` in `~/.config/mickey/config.toml` (a
backup is kept, last 10) and runs `mickey arranged`, which also tells the other PCs.
When only a PC moved, `monitors.lua` and Hyprland are left alone.

### espanso: your triggers on the other PC

A text expander such as [espanso](https://espanso.org) reads the keyboards itself.
While the keyboard is on another PC, Mickey holds them, so espanso hears nothing and
your triggers stop working there. To make them work:

```bash
~/.config/omarchy/plugins/io.github.rob-d3v.omakvm/bin/omakvm espanso on
```

It asks for your password once and:

1. replaces Mickey in `~/.local/bin` with the fork (the official build is kept beside
   it and `omakvm espanso off` puts it back);
2. installs a udev rule so the desktop ignores a new virtual keyboard, *Mickey typing
   mirror* (`LIBINPUT_IGNORE_DEVICE`);
3. starts Mickey with `MICKEY_TYPING_MIRROR=1`: what you type for the other PC is
   repeated on that mirror, which only espanso reads. espanso sees the trigger and
   types the expansion through its own virtual keyboard, which Mickey sends to the
   other PC like any key;
4. sets espanso to `backend: Inject`, so an expansion is typed key by key. Otherwise
   espanso pastes long text from this PC's clipboard with Ctrl+V, and the other PC
   has another clipboard;
5. turns Mickey's self-update off on this PC, since it would put the official build back.

`omakvm espanso status` says what is in place. Both PCs need the same keyboard
layout, since the text arrives as keys. Passwords typed this way also pass through
the mirror, which programs in the `input` group can read, like the keyboard itself.

### A PC without a screen for the code: Add over SSH

Pairing in Mickey means comparing a code on both screens. A board behind a wall
display or a kiosk has nobody to press *Pair*. If you already reach that PC by SSH,
that connection can vouch for it instead:

```bash
P=~/.config/omarchy/plugins/io.github.rob-d3v.omakvm
$P/bin/omakvm add-ssh user@192.168.0.20
$P/bin/omakvm add-ssh --name "Wall display" -i ~/.ssh/id_ed25519 user@192.168.0.20
```

The panel's **Add PC → Over SSH** opens a terminal with the same command (pick the
SSH key there, or leave it on automatic and type the password when ssh asks). It:

1. opens one SSH connection and looks at that PC: architecture, system, who owns the
   screen. A PC it cannot serve is told apart here, before anything is changed
   (see *What it cannot do* below);
2. copies Mickey to `~/.local/bin` there (the official release on x86-64; on ARM64, a
   build of the same source, see below) and writes a `config.toml` that only lets the
   PC be controlled (`controls_others = false`);
3. runs one step with `sudo` there, which may ask for that user's password: the uinput
   udev rule, the `input` group, `libpulse0` if it is missing, the firewall ports if
   ufw is on, and the service;
4. reads each PC's public Mickey key over SSH and writes it into the other's
   `trusted_peers`, which is what pressing *Pair* on both screens does, and adds the
   PC as a peer here. A PC flashed again since it was paired gets its new key;
5. waits for the PC to come online and says what it found.

With the panel open, the new PC appears to the right of your screens, already saved,
so the cursor reaches it at once. Drag it where it really sits and **Save**.

The SSH key that worked for a PC is remembered (`~/.cache/omakvm/ssh-keys`). Keys are
never tried one after another: a server that sees several fail starts refusing the
connection.

Two kinds of target are told apart on their own (`--kiosk` / `--session` override):

- **A session of your own** (a desktop or a headless board): a systemd user service.
- **A kiosk**, where the screen belongs to an X server another user started (root,
  usually): a system service that still runs as your SSH user, in the `input`
  group, and is handed a copy of the X server's access cookie when it starts.
  Without it Mickey could type but not see the kiosk's monitors or clipboard, and
  the cursor could not cross at an edge.

What it cannot do:

- **ARMv6 boards** (Raspberry Pi 1 and Zero) and 32-bit x86.
- **glibc older than** 2.28 on 32-bit ARM, 2.36 on ARM64, 2.35 on x86-64.
- **A Wayland kiosk without the RemoteDesktop portal** gets the keyboard and mouse,
  but Mickey cannot learn its monitors, so there is no edge to cross: use the hotkeys.

A **32-bit ARM system** (a Raspberry Pi with a 32-bit Raspberry Pi OS, also under a
64-bit kernel) is served by the fork described below: Mickey's own source reads and
writes the kernel's input events in their 64-bit layout only.

To undo it on that PC:

```bash
sudo systemctl disable --now mickey.service; sudo rm -f /etc/systemd/system/mickey.service   # kiosk
systemctl --user disable --now mickey.service; rm -f ~/.config/systemd/user/mickey.service    # session
rm -rf ~/.local/bin/mickey ~/.local/bin/mickey-ui ~/.config/mickey ~/.local/share/mickey
sudo rm -f /etc/udev/rules.d/99-mickey-uinput.rules
```

and remove the PC in the panel here.

### The builds this repository publishes

Mickey publishes x86-64 builds of its own. The releases here carry what is missing:

| File | What it is | For |
| --- | --- | --- |
| `mickey-linux-aarch64.tar.gz` | Mickey's source at the release's tag, **unchanged** | ARM64 PCs added over SSH |
| `mickey-fork-linux-armv7.tar.gz` | the fork | 32-bit ARM PCs added over SSH |
| `mickey-fork-linux-x86_64.tar.gz` | the fork | `omakvm espanso on` on this PC |

**The fork** is [rob-d3v/mickey, branch `omakvm`](https://github.com/rob-d3v/mickey/tree/omakvm):
Mickey v0.4.5 plus three changes, in one commit:

- **32-bit Linux.** `ioctl`'s request and the time at the start of `struct input_event`
  are C `long`s, 4 bytes narrower there.
- **Devices plugged in later.** Mickey looks for its keyboards once, when it starts.
  The fork looks again every 2 s: a keyboard that drops off a USB hub and comes back,
  or a text expander that restarts with a new virtual keyboard, is picked up, and
  grabbed if the focus is away.
- **The typing mirror**, off unless `MICKEY_TYPING_MIRROR=1` (see *espanso* above in this page).

Every tarball has `SOURCE-COMMIT` (the commit it was built from) and Mickey's GPL-3.0
`LICENSE`. Build your own with [`packaging/build-aarch64.sh`](packaging/build-aarch64.sh)
and [`packaging/build-fork.sh`](packaging/build-fork.sh) (they need docker), and pass
the result with `--from`:

```bash
packaging/build-fork.sh armv7
bin/omakvm add-ssh --from dist/mickey-fork-linux-armv7.tar.gz user@192.168.0.20
```

Mickey's own updater knows only its x86-64 release, so a PC set up here does not
update itself: run `add-ssh` (or `espanso on`) again with a newer build.

## Good to know

- **Same keyboard layout on both PCs.** Mickey sends keys by position.
- **Local network only.** Mickey has no relay; neither has this.
- **The cursor crosses where the tiles touch**, over the length they share. A PC
  placed off to one side with a gap is reached with the hotkeys only.
- **Text expanders** need `omakvm espanso on` to see what you type on another PC.
- **Try** applies the screens only. PCs move when you **Save**.
- Mickey's own limits (Windows secure screens, GNOME's clipboard, touchpad taps) are
  in [its README](https://github.com/EduardoMG12/mickey#known-limits).

## Remove

```bash
omarchy plugin remove io.github.rob-d3v.omakvm
```

Mickey stays; to remove it too, run `uninstall.sh` from
[its release](https://github.com/EduardoMG12/mickey/releases/latest), then
`sudo rm /etc/udev/rules.d/99-mickey-uinput.rules` and `sudo gpasswd -d "$USER" input`.

## Development

```
manifest.json        plugin manifest (kinds: panel, bar-widget)
Panel.qml            the panel: canvas, sidebar, add PC, try and save
Widget.qml           bar icon that follows `mickey status --waybar`
PlainText.qml        every text in the panel: plain text, never markup
Model.js             screens: layout and monitors.lua logic (Monitor Manager)
Net.js               network PCs: Mickey's output, config.toml, placement
bin/omakvm           install Mickey, add a PC over SSH, doctor
i18n/                en.json, pt-BR.json
packaging/           builds of Mickey: ARM64 (unchanged) and the fork
test/                node tests for Model.js and Net.js
```

```bash
node test/model.test.js && node test/net.test.js
omarchy plugin validate .
```

Changed QML is only picked up reliably after `omarchy restart shell`.

## License

[MIT](LICENSE). The screens code is © 2026 Fabio Cuccaro; see [NOTICE](NOTICE).
Mickey is a separate program under GPL-3.0-or-later and is not part of this
repository's source. The tarballs attached to releases are Mickey (unchanged, or
the fork at https://github.com/rob-d3v/mickey), under Mickey's own license.
