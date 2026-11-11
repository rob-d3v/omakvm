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

- **32-bit systems** (a Raspberry Pi running a 32-bit Raspberry Pi OS, even on a
  64-bit kernel). Mickey writes the kernel's 64-bit input events; it needs a 64-bit
  system image.
- **glibc older than 2.31** on ARM64, or 2.35 on x86-64.
- **A Wayland kiosk without the RemoteDesktop portal** gets the keyboard and mouse,
  but Mickey cannot learn its monitors, so there is no edge to cross: use the hotkeys.

To undo it on that PC:

```bash
sudo systemctl disable --now mickey.service; sudo rm -f /etc/systemd/system/mickey.service   # kiosk
systemctl --user disable --now mickey.service; rm -f ~/.config/systemd/user/mickey.service    # session
rm -rf ~/.local/bin/mickey ~/.local/bin/mickey-ui ~/.config/mickey ~/.local/share/mickey
sudo rm -f /etc/udev/rules.d/99-mickey-uinput.rules
```

and remove the PC in the panel here.

### ARM64

Mickey publishes x86-64 builds only. For ARM64 targets (Raspberry Pi and the like),
this repository's releases carry `mickey-linux-aarch64.tar.gz`: Mickey's source at
the tag named in the release, unchanged, compiled by
[`packaging/build-aarch64.sh`](packaging/build-aarch64.sh) (Debian bullseye,
glibc 2.31). `SOURCE-COMMIT` inside the tarball names the commit, and Mickey's
GPL-3.0 `LICENSE` is in it. Build your own and pass it with `--from` if you prefer:

```bash
packaging/build-aarch64.sh v0.4.5
bin/omakvm add-ssh --from dist/mickey-linux-aarch64.tar.gz user@192.168.0.20
```

Mickey itself does not update an ARM64 install (its updater looks for the x86-64
release); run `add-ssh` again with a newer tarball.

## Good to know

- **Same keyboard layout on both PCs.** Mickey sends keys by position.
- **Local network only.** Mickey has no relay; neither has this.
- **The cursor crosses where the tiles touch**, over the length they share. A PC
  placed off to one side with a gap is reached with the hotkeys only.
- **Text expanders.** While the keyboard is on another PC, Mickey holds your real
  keyboard, so an expander on this PC may not see what you type. What it types
  through its own virtual keyboard does travel if that keyboard existed when Mickey
  started. The clipboard always follows: copy here, cross, paste there.
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
packaging/           the ARM64 build of Mickey
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
repository's source; the ARM64 tarball attached to releases is Mickey, under its
own license.
