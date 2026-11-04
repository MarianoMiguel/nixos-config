# NixOS Config

Personal NixOS workstation and installer configuration.

For remote administration, the four Claude/Codex subscription profiles, chat
handoff, connectors and pre-departure recovery tests, see
[Bonhart remote workstation](docs/remote-workstation.md).

## Systems

- `#standard`: portable workstation install for new machines.
- `#bonhart`: same workstation profile with Bonhart-specific runtime fixes.
- `#balerion`: gaming PC profile for the Intel 13900KF and RTX 3080 Ti.
- `#balerion-install`: Balerion with the guided installer's encrypted disk layout.
- `#bonhart-install`: Bonhart with encrypted root plus 64 GiB hibernation swap.
- `#installer`: graphical guided installer ISO carrying both complete systems.

The `#balerion` output keeps its existing storage configuration. Bonhart uses
the guided installer's encrypted LVM layout. After a guided install, the
installer also saves the selected encrypted layout as that machine's
`hosts/<machine>/storage.nix`. That file is git-ignored, except Bonhart's, which
is committed (it names no disks or secrets) because Update All builds only
committed files.

## Build The Installer

```sh
./scripts/build-installer-iso.sh                 # dual image, installs either machine
./scripts/build-installer-iso.sh --host bonhart  # single-machine image, ~half the time
```

The script evaluates the complete flake, builds the encrypted install outputs
the image will embed, then builds from a snapshot of the current workspace
(including new files not committed yet, but without `.git`, agent worktrees
under `.claude/`, build results or payload archives). A stale `flake.lock`
fails the build; run `nix flake lock` first. It prints the finished ISO path under
`result-installer/iso/`. Set `SKIP_VALIDATION=1` only for an intentional ISO-only
rebuild.

When the target machine is known, prefer `--host balerion` or `--host bonhart`:
the image embeds only that machine's closure, roughly halving build time, ISO
size and USB write time, and the wizard skips the machine question. Build on
Balerion when possible; it is by far the faster builder.

The build refuses to start without roughly 40 GiB of free disk space (25 GiB
for a single-host image), since the ISO embeds complete workstation closures,
and prints the final ISO size.

To write the ISO to a USB drive, pick the drive interactively and use the
newest built ISO:

```sh
sudo ./scripts/write-installer-usb.sh
```

Everything can also be passed explicitly, including payload files for the
remaining USB space:

```sh
sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/<usb-disk> result-installer/iso/mariano-nixos-installer.iso /path/to/mariano-personal-payload.tar.zst.age
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

The ISO includes the pinned flake inputs, Disko scripts, and the complete
closure of every machine it was built for (both machines on the dual image, one
on a `--host` image). Installation therefore runs with Nix offline and does not
depend on a binary-cache download. Generated NixOS documentation and the man-page cache
are disabled in workstation builds to avoid the documentation derivation that
previously made recovery installs fragile.

### Bonhart kernel and Wi-Fi stability

Bonhart tracks the newest maintained LTS kernel (`linuxPackages_6_18`) so the
Strix Point s2idle and amdgpu paths keep receiving fixes without outrunning
DisplayLink's out-of-tree `evdi` module. Its Wi-Fi uses the in-tree `mt7925e`
driver; the earlier out-of-tree MT7925 package was dropped once mainline caught
up. A future kernel-series change must still build EVDI before activation.

Bonhart also sets the Argentina wireless regulatory domain, disables Wi-Fi
power saving and MT7925 PCI ASPM, and keeps redistributable firmware current
with the pinned NixOS release. The existing AMD `dcdebugmask=0x810` workaround
stays a runtime kernel parameter and therefore does not invalidate the cached
kernel. Workstation systems retain five systemd-boot generations, run weekly
garbage collection for store paths older than 14 days, and automatically
optimise the Nix store.

Bonhart enables DisplayLink (`mariano.displaylink.enable = true` in the
committed `hosts/bonhart/common.nix`, so a checkout outside `/etc/nixos` sees
it) for the Elgato Prompter. Synaptics requires accepting a separate EULA and
the driver archive cannot legally be redistributed inside the ISO, so before
the first build accept the vendor terms and add the pinned archive to the local
Nix store:

```sh
nix-prefetch-url --name displaylink-620.zip 'https://www.synaptics.com/sites/default/files/exe_files/2025-09/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.2-EXE.zip'
```

After installation, remove the USB drive and reboot. The firmware will ask for
the LUKS password; the desktop uses Mariano's password; `sudo` and admin prompts
(polkit) use the separate administrator password.

## Desktop

GNOME is the desktop, extended with GNOME Shell extensions packaged or pinned
in this repository: Vicinae's companions, AppIndicator for tray apps, Dash to
Dock and CodexBar's quota indicator (`modules/nixos/gnome.nix`,
`modules/nixos/vicinae.nix`, `extensions/`). Plasma, Blueman,
NetworkManager's tray applet, Discover and PackageKit are deliberately not
installed as competing control surfaces. KDE applications such as Dolphin,
Krita and Kdenlive remain available and follow the same light/dark
appearance; Qt apps draw Interstellar's title bar
(`packages/qt-interstellar-decorations`).

The earlier niri desktop (Dank Material Shell, the Folio shell, the design
workshop and Pond) is archived on the `archive/interstellar-niri` branch.

### Login screen

The login screen is still DMS's greeter, running in a bare niri under greetd
and drawn in Interstellar's look (`modules/nixos/login-screen.nix`,
`patches/dms-azure-folio-greeter.patch`). GNOME is the only session it
offers. It stays until a GDM login screen is styled to match the disk-unlock
screen. A system switch preserves the running greeter; the rebuilt one
appears when greetd next starts (normally after reboot).

### Launcher and shortcuts

`Alt+Space` opens Vicinae, the application launcher; `Alt+[`, `Alt+]` and
`Alt+'` center, almost-maximize and hide the other windows. A tap on `Super`
opens Activities. `Alt+A` dictates into the focused window and `Alt+S` talks
to the voice agent (below). keyd's Alt layer turns `Alt+D`/`Alt+U` into
Page Down/Up and `Alt+Left`/`Alt+Right` into Home/End everywhere.

cmux Browser is installed with the workstation applications. Launch `cmux`
or `cmux-browser`, or search for cmux in the app launcher; `cmux-tui` exposes
its terminal control CLI. The Nix package pins the official Linux nightly's
version and SHA-256 in `packages/cmux-browser.nix`, patches its libraries for
NixOS, and retains Chromium's user-namespace sandbox. Updates are managed by
changing that package pin and rebuilding, rather than the in-app updater.
Chrome remains the default web browser.

### Update All

`sudo mariano-system-update-all` updates the system; twice a week a
notification reminds you when the locked nixpkgs is more than two weeks old.
It refreshes every movable flake input—including Codex Desktop—before
building and switching. It builds only committed code. It resolves
`/etc/nixos` to the administrator's checkout, rejects unsafe ownership or
permissions, and refuses a checkout with uncommitted changes or with `.nix`
files git does not track (untracked or ignored), since a build from git
would leave them out. As the checkout owner it updates the inputs, commits
the new `flake.lock` (`flake.lock: update all inputs`, local until you push),
lists the commits since the deployed generation, and builds that exact commit
(`git+file://…?rev=…`); root only activates the result. Each generation
records its commit (`nixos-version --configuration-revision`), and
`/var/lib/mariano-system-update/deployed-commit` keeps the last one deployed.
If the build or the switch fails, the lock commit is undone. Explicitly
commit-pinned inputs remain pinned; `sudo mariano-system-update` remains
available for a narrow update of only `nixpkgs`, Home Manager and Disko.

The guided installer already installs Steam and Proton VPN as part of the
workstation closure.

### Reminders, dictation and quotas

`mariano-reminder` sets, lists and clears reminders (`mariano-reminder
interactive` for a menu). They are stored in a private local queue and
delivered by a persistent user timer, so locking, sleeping or rebooting does
not discard them.

For dictation, focus any text field, tap `Alt+A`, speak, then tap `Alt+A` again
to stop; a short silence also ends the recording automatically. Speech is
transcribed by the pinned local Whisper model and typed into the window that
was focused when dictation began. `Alt+S` is the separate spoken-agent mode,
which opens a visible Claude Code terminal instead of typing a transcription.
Under GNOME the agent finds and focuses its terminal through the Vicinae
GNOME extension's window service; its floating level panel needs a
layer-shell compositor, so GNOME's microphone indicator is the only cue.

The CodexBar GNOME extension shows the Claude and Codex quotas in the top
bar, through the system's `codexbar` CLI with each tool's OAuth sign-in. It
does not crawl AI transcripts or provide an agent launcher.

### Screenshots, idle and locking

GNOME's own screenshot and screencast tool (`Print`) captures the screen, a
window or a region; `Shift+Ctrl+Alt+R` opens it for a screencast.

GNOME owns idle, blanking and the lock screen. `modules/nixos/power.nix`
mirrors the hibernate-only policy into GNOME: idle never sleeps on AC, so
long plugged-in builds finish; idle on battery hibernates; a closed lid
hibernates, except on AC on Bonhart (`modules/nixos/remote-workstation.nix`),
which stays online as an unattended host.

### Bonhart fingerprint enrollment

Bonhart enables `fprintd` for the login screen, console login and `sudo`.
Admin prompts (`polkit`) take only the administrator password. Run
`mariano-fingerprint-manager` in a terminal to list, enroll or delete prints.
Mariano's account owns login fingerprints. Because `sudo` intentionally
authenticates against the separate root account, its submenu uses NixOS's
root-owned security wrapper and should enroll a different finger for
administrator authentication.

Passwords remain available as the fallback. Enrollment still needs to be
performed on the physical ThinkPad because the reader must capture the finger.

### Interstellar's look

The look is a theme, a mode and one color: **Folio** (art printed in ink on
paper, with three art collections: **Doré**, **European Summer** and
**Argentina**, two plates each, plus your own pictures from
`~/Pictures/Folio`) or **Lumen**, each in **Daylight / After hours**. All
share Inter for the interface, IBM Plex Mono for terminals and captions, and
Jacquard 24 for the large clock.

```sh
azure-folio set --collection summer --mode light --ink azure
azure-folio next
azure-folio set --theme lumen --mode dark --accent green
azure-folio status
azure-folio restore
```

Each change applies the palette to apps through themeport (`themeport look`),
puts a Folio plate on GNOME's desktop, and publishes the selection for the
login screen and the disk-unlock screen (`docs/folio-boot.md`). Under GNOME a
Lumen selection keeps the current wallpaper; its sky was drawn by the
archived Folio shell.

The six palette slots are implementation details in Themeport's closed,
immutable catalog. Art and fonts are bundled offline.
`tools/azure-folio/build.py` creates deterministic two-color
Atkinson-dithered wallpapers at build time; switching never calls an
image-generation service. Source credits and original illustration prompts
are in `assets/azure-folio/`.

Themeport does not register browser URL handlers, download executable themes,
install theme-declared VS Code extensions or load mutable third-party catalogs.
Chrome receives only a validated theme-color policy.

## Personal Payload

Secrets and large personal data are not stored in Nix or committed to git.
Create a payload archive separately. It is encrypted with a passphrase you
choose (age), because the installer USB's payload partition is exFAT and
cannot protect the SSH keys and tokens inside with file permissions:

```sh
./scripts/create-personal-payload.sh /path/to/usb-or-backup
```

If no destination is passed, the script writes to `~/nixos-usb-payload` so it
does not accidentally archive its own output inside `~/Development`.

Restore it after install; the script asks for the passphrase:

```sh
sudo ./scripts/restore-personal-payload.sh /path/to/mariano-personal-payload.tar.zst.age /home/mariano
```

The payload includes `~/Development`, SSH keys, nvm/npm state, and selected
developer app auth/config directories when they exist. Archives made before
payloads were encrypted (`.tar.zst`) still restore.

## Backups

`modules/nixos/backups.nix` snapshots `/home/mariano` with restic every night
at 03:00 plus up to an hour of jitter, catching up after sleep, and keeps 7
daily, 4 weekly and 6 monthly snapshots. Caches, package stores, container
images, game libraries and model weights are excluded. The destination and its
credentials live outside the repository, so the job stays inert until both
files below exist:

```sh
# Any restic repository: a mounted disk path, sftp:, rest:, s3:, b2:, ...
echo 's3:https://s3.us-west-004.backblazeb2.com/my-bucket/bonhart' | sudo tee /var/lib/restic/repository
# Credentials the repository needs, as KEY=value lines (leave empty for paths).
sudo install -m 0600 /dev/null /var/lib/restic/environment
# The repository password. Save it in the password manager first: without it
# every snapshot is unreadable, and it must survive losing this disk.
sudo sh -c 'umask 077; printf %s "$(openssl rand -base64 32)" > /var/lib/restic/password'

sudo systemctl start restic-backups-home   # first run initialises the repository
sudo restic-home snapshots                 # wrapper preloaded with the same settings
```

## Validate

```sh
nix flake check
nixos-rebuild dry-build --flake .#standard
```

`nix flake check` also runs every script in `tests/` as a hermetic derivation,
plus `interstellar-boot` for the boot look. Run one on its own with
`nix build .#checks.x86_64-linux.system-update`.
