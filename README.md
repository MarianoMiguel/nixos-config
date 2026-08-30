# NixOS Config

Personal NixOS workstation and installer configuration.

## Systems

- `#standard`: portable workstation install for new machines.
- `#bonhart`: same workstation profile with Bonhart-specific runtime fixes.
- `#balerion`: gaming PC profile for the Intel 13900KF and RTX 3080 Ti.
- `#balerion-install`: Balerion with the guided installer's encrypted disk layout.
- `#bonhart-install`: Bonhart with encrypted root plus 64 GiB hibernation swap.
- `#installer`: graphical guided installer ISO carrying both complete systems.

The `#balerion` output keeps its existing storage configuration. Bonhart now uses
the guided installer's encrypted LVM layout by default. After a guided install,
the installer also saves the selected encrypted layout as that machine's local
`storage.nix`, which is intentionally not committed.

## Build The Installer

```sh
./scripts/build-installer-iso.sh
```

The script evaluates the complete flake, builds both existing machine outputs and
both encrypted install outputs, then builds from the literal current workspace
(including new files not committed yet). It prints the finished ISO path under
`result-installer/iso/`. Set `SKIP_VALIDATION=1` only for an intentional ISO-only
rebuild.

The build refuses to start without roughly 40 GiB of free disk space, since the
ISO embeds both complete workstation closures, and prints the final ISO size.

To write the ISO to a USB drive, pick the drive interactively and use the
newest built ISO:

```sh
sudo ./scripts/write-installer-usb.sh
```

Everything can also be passed explicitly, including payload files for the
remaining USB space:

```sh
sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/<usb-disk> result-installer/iso/mariano-nixos-installer.iso /path/to/mariano-personal-payload.tar.zst
```

## Install A Machine

Boot the custom installer in UEFI mode. The guided installer opens automatically;
the desktop shortcut or this command reopens it:

```sh
sudo install-mariano-nixos
```

The wizard asks for:

1. Balerion or Bonhart.
2. The whole target disk. The booted installer disk is excluded.
3. A LUKS disk-unlock password.
4. Mariano's login password.
5. A separate administrator password used by `sudo`.
6. An exact final erase confirmation.

The selected disk is completely erased. Balerion receives a 1 GiB UEFI partition
and an encrypted ext4 root. Bonhart receives the same UEFI partition plus one
encrypted LVM container with a 64 GiB hibernation swap volume and an ext4 root.

The ISO includes the pinned flake inputs, Disko scripts, and both complete target
system closures. Installation therefore runs with Nix offline and does not depend
on a binary-cache download. Generated NixOS documentation and the man-page cache
are disabled in workstation builds to avoid the documentation derivation that
previously made recovery installs fragile.

### Bonhart kernel and Wi-Fi stability

Bonhart intentionally uses the stock NixOS 6.18 LTS kernel so kernel updates
come from the binary cache. Its MT7925 fixes are packaged separately from the
kernel using the pinned
[`zbowling/mt7925` v1.5.0 driver](https://github.com/zbowling/mt7925/tree/v1.5.0).
Only those Wi-Fi modules rebuild when the kernel ABI changes; the full kernel
does not.

Bonhart also sets the Argentina wireless regulatory domain, disables Wi-Fi
power saving and MT7925 PCI ASPM, and keeps redistributable firmware current
with the pinned NixOS release. The existing AMD `dcdebugmask=0x810` workaround
stays a runtime kernel parameter and therefore does not invalidate the cached
kernel. Workstation systems retain five systemd-boot generations, run weekly
garbage collection for store paths older than 14 days, and automatically
optimise the Nix store.

Bonhart leaves DisplayLink disabled because Synaptics requires
accepting a separate EULA and the driver archive cannot legally be redistributed
inside the ISO. To enable it, accept the vendor terms, add the pinned archive to
the local Nix store, then change `mariano.displaylink.enable` to `true` in the
machine-local `hosts/bonhart/storage.nix` before rebuilding:

```sh
nix-prefetch-url --name displaylink-620.zip 'https://www.synaptics.com/sites/default/files/exe_files/2025-09/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.2-EXE.zip'
```

After installation, remove the USB drive and reboot. The firmware will ask for
the LUKS password; the desktop uses Mariano's password; `sudo` uses the separate
administrator password.

## Consistent Desktop And System Actions

Niri and Dank Material Shell are the primary desktop. DMS owns networking,
Bluetooth, audio, displays, wallpaper, notifications and quick settings. GNOME
remains a stock fallback session, but Plasma, Blueman, NetworkManager's tray
applet, Discover and PackageKit are deliberately not installed as competing
control surfaces. KDE applications such as Dolphin, Krita and Kdenlive remain
available and follow the same GTK-derived light/dark appearance.

`Alt+Space` opens the Vicinae application launcher in Niri and GNOME;
`Super+Period` is a second Niri spelling. `Super+Space` opens the separate,
searchable System Actions menu in both sessions. System actions are not
exported as fake applications, so they no longer crowd Vicinae's results.
`mariano-system-menu --categories` offers the same commands as a browsable
nested menu. Important entries include:

- safe laptop-display toggle, which refuses to turn off the only active screen;
- DMS display/network settings, Wi-Fi and Bluetooth toggles, and Proton VPN;
- full, region and video capture plus a remembered system-audio toggle;
- DMS Power & Sleep settings plus a Focus menu for notification silence,
  `Stay awake`, reminders, local dictation and Night Light;
- immediate lock, lock-screen preview, and lock/screen-saver settings;
- the 22 pinned official Omarchy themes (including Osaka Jade), their bundled
  non-wordmark wallpapers, and window border/gap toggles;
- fingerprint enrollment on Bonhart; and
- a fixed NixOS updater that updates only `nixpkgs`, Home Manager and Disko,
  rejects a writable or symlinked `/etc/nixos`, restores the old lock file on
  failure, and leaves third-party inputs pinned.

The guided installer already installs Steam and Proton VPN as part of the
workstation closure.

### Fast motion and focus controls

Niri transitions use fixed 40–70 ms timings instead of open-ended springs.
DMS uses a 40 ms custom base, so its largest expressive transition is 80 ms;
notification and AI-quota feedback use 60 ms. Long-running spinners and active
recording/dictation indicators keep their slower cycles because they describe
ongoing work rather than delaying an interaction.

Search `Focus` with `Super+Space` for notification silence (toggle, one hour, or
until 08:00 tomorrow), resume notifications, `Stay awake`, reminders,
dictation and Night Light. DMS shows active Do Not Disturb and idle-inhibitor
state in the control center. Reminders are stored in a private local queue and
delivered by a persistent user timer, so locking, sleeping or rebooting does
not discard them.

For dictation, focus any text field, tap `Alt+A`, speak, then tap `Alt+A` again
to stop; a short silence also ends the recording automatically. Speech is
transcribed by the pinned local Whisper model and typed into the window that
was focused when dictation began. `Alt+S` is the separate spoken-agent mode,
which opens a visible Claude Code terminal instead of typing a transcription.

The CodexBar panel keeps its reviewed OAuth-only quota source, but now presents
Claude, Codex and any other provider through a compact provider switch and one
focused quota card at a time. It does not crawl AI transcripts or provide an
agent launcher.

### Screenshots and screen recording

The Niri session has one consistent capture workflow:

- `Alt+Shift+3` captures all displays;
- `Alt+Shift+4` selects and captures a region; and
- `Alt+Shift+5` selects a region and starts recording. Press it again to stop
  and finalize the video.

Screenshots are saved privately in `~/Pictures/Screenshots` and copied to the
clipboard. Recordings are saved privately in `~/Videos/Recordings`. System
audio defaults to off for privacy. Search for `System · Capture · Toggle system
audio in recordings` with `Super+Space` to enable or disable it for future
recordings; that preference survives reboot. The recorder follows the current
default audio output, so it continues to work when switching between speakers,
headphones and a dock.

Recording runs only while a capture is active, without root privileges, KMS
capabilities, a plugin loader or network access. The persistent notification
shows whether audio is included and reminds you how to stop. The same
notification is replaced with the saved file path after the recorder has
finished writing the MP4.

DMS remains the single idle-policy owner. Fresh installs lock after ten minutes
on AC or five minutes on battery, then power off the displays after another
minute or thirty seconds respectively. Existing installations receive that
baseline once and can subsequently change it in DMS Power & Sleep. Automatic
suspend stays disabled, matching Bonhart's fail-closed hibernation policy and
avoiding a second Wayland idle daemon with competing state.

The lock screen is intentionally minimal: time and authentication stay visible;
power actions, system icons, date, profile image, media controls and notification
content are hidden. The old five-second fade is disabled. Search for `Preview
lock screen` or `Lock screen & screensaver settings` to inspect it and configure
DMS's optional video screensaver without creating a second idle daemon.

### Bonhart fingerprint enrollment

Bonhart enables `fprintd` for greetd login, DMS unlock, `polkit` authorization
and `sudo`. Open `Super+Space`, then `Security · Set up fingerprints` to list,
enroll or delete prints. Mariano's account owns login and unlock fingerprints.
Because `sudo` intentionally authenticates against the separate root account,
its submenu uses NixOS's root-owned security wrapper and should enroll a
different finger for administrator authentication.

The DMS lock screen exposes password and fingerprint as independent parallel
methods: typing Mariano's password never waits for or consumes a fingerprint
attempt, and touching the enrolled finger does not require opening the password
field first.

Passwords remain available as the fallback. Enrollment still needs to be
performed on the physical ThinkPad because the reader must capture the finger.

### Niri Picture-in-Picture

Browser Picture-in-Picture windows are managed by the pinned niri-pip v0.2.1
daemon. It recognizes Firefox and Chromium-family PiP windows, floats them
without taking keyboard focus, remembers their geometry and follows the active
Niri workspace. Search for
`System · Windows · Picture-in-Picture controls` with `Super+Space` to resize,
position, lock or change the follow behavior. `System · Windows · Toggle
pin focused window` makes any focused window follow you until it is unpinned.

The package and user service are fully declarative. The upstream installer,
updater and config mutation scripts are not used; the service is Niri-only,
rootless, limited to Unix sockets and sandboxed to its geometry state plus its
generated opacity rule. Multi-monitor follow modes other than the default
`follow-workspace` remain opt-in because they need testing on the physical
display layout.

### Niri scratchpads

Press `Super+Shift+S` to move the focused window into the scratchpad for the
current display. Press `Super+S` to summon it as a centered floating window;
press the same shortcut while it is focused to hide it again. Each display has
an independent stack, so moving a window on the laptop panel never replaces the
scratchpad on an external monitor. When a stack contains several windows,
hiding the current one rotates to the next window for the following summon.

The controller talks only to Niri's local IPC socket and stores window IDs in a
private per-login runtime directory. It has no daemon, network access, plugin
loader or elevated privileges. Its storage workspace is created at the bottom
of each display only when first used, preserving the existing numbered
workspace positions at login. Niri does not yet support truly hidden
workspaces, so that storage workspace remains visible in the overview.

### Niri workspace modes

Every workspace has one of three window modes, switched per monitor from the
`Workspace Modes` widget at the right of the DankBar or with `Mod+Alt+Space`
(cycle), `Mod+Alt+T` (tile), `Mod+Alt+F` (float) and `Mod+Alt+Return` (focus):

- **Tile** is Niri's native scrollable tiling and the passive default: with a
  workspace in tile mode the daemon changes nothing.
- **Float** floats every window on the workspace, including ones that open
  later. `Super+drag` moves a window, `Super+right-drag` resizes it.
- **Focus** merges the workspace into a single centered tabbed column at 80%
  width (`mariano.workspaceModes.focusWidth`), so exactly one app is visible
  with wallpaper on both sides and zero neighbor peek. `Mod+Alt+Scroll` (or
  the usual in-column focus keys) steps one app per notch.

Modes apply to exactly one workspace. The `niri-modes` daemon holds the state
per workspace ID and enforces it with per-window IPC actions, so switching the
mode on one monitor can never restyle the workspace showing on another. Shell
surfaces, portals and Picture-in-Picture windows are exempt from enforcement.
Mode state is in-memory and resets with the session; the daemon is Niri-only
and talks solely to Niri's local IPC socket plus its own private Unix socket
(in the per-login runtime directory) for the widget and CLI.

### Theme security and Omarchy lessons

Themeport exposes a closed catalog copied into the immutable Nix store. It no
longer registers `aether://` browser links, downloads themes, consumes runtime
plugin catalogs, installs VS Code extensions declared by a theme, or links
user-writable color files into Chromium managed-policy directories. DMS may run
its built-in Matugen templates, but mutable user templates and third-party
launcher results are forced off. Existing DMS integrations are flake-pinned
source inputs built with the OS, not marketplace-installed runtime plugins.

The useful parts borrowed from Omarchy are one shell owning common controls,
grouped searchable actions, a single theme switcher and a visible update path.
The runtime plugin registry, executable theme hooks and unreviewed package/theme
sources are intentionally excluded. See Omarchy's official documentation for
its [menu and command model](https://github.com/basecamp/omarchy/blob/quattro/default/omarchy-skill/SKILL.md),
[themes](https://github.com/basecamp/omarchy/blob/quattro/manual/06-themes.md),
[top bar](https://github.com/basecamp/omarchy/blob/quattro/manual/05-the-top-bar.md),
and [updates](https://github.com/basecamp/omarchy/blob/quattro/manual/30-updates.md).

## Personal Payload

Secrets and large personal data are not stored in Nix or committed to git.
Create a payload archive separately:

```sh
./scripts/create-personal-payload.sh /path/to/usb-or-backup
```

If no destination is passed, the script writes to `~/nixos-usb-payload` so it
does not accidentally archive its own output inside `~/Development`.

Restore it after install:

```sh
sudo ./scripts/restore-personal-payload.sh /path/to/mariano-personal-payload.tar.zst /home/mariano
```

The payload includes `~/Development`, SSH keys, nvm/npm state, and selected
developer app auth/config directories when they exist.

## Validate

```sh
nix flake check
nixos-rebuild dry-build --flake .#standard
```
