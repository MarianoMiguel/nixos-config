# Interstellar boot and disk-unlock screen

`mariano.folio.boot.enable` (in `modules/nixos/folio-boot.nix`, imported by
Bonhart) replaces the bare console LUKS prompt with Interstellar's page:
Plymouth with the `interstellar` theme (`packages/plymouth-folio`), in the
owner's look. A look is a theme (Folio or Lumen), a mode (light or dark),
one color and, for Lumen, its sky, resolved by `tools/azure-folio/looks.py`
exactly as the desktop resolves it. Off, the system builds as it did before
the boot screen.

## What it shows

The lock screen's split in every theme: the theme's art on the left (56 %),
the page on the right.

- **Folio**: the plate printed in the look's ink at the screen's exact pixel
  size, and the paper page with the machine's name tab hanging from its top
  edge. "Encrypted disk", then **Unlock Bonhart's disk**, a rule, and a well
  that prints one ink dot per typed character with a breathing caret.
- **Lumen**: its sky, drawn as the shell's `shaders/lumen.frag` draws it,
  pixel for pixel, in the accent's hue and three neighbours: **orbit** (a
  tilted ring of light with a soft trail, the default), **prism** (ribbons
  of light seen through diagonal fluted glass), **glow** (one soft luminous
  shape) or **haze** (a full-bleed gradient), near black at night and pale
  grey by day, each with the shader's still film grain. Beside it, a plain
  page in the window color: a
  neutral pill with the laptop and the machine's name, "Disk encrypted",
  **Unlock** in Inter Bold, "Type Bonhart's passphrase to start.", and a pill
  field with dots in the text color, a blinking accent caret and a round
  accent button with an arrow. At the foot: "US keyboard · Esc shows the boot
  messages".

In both, the field shakes when the disk refuses a passphrase, with "That
passphrase didn't unlock the disk. Try again."; "Checking the passphrase…"
while it checks; "Caps Lock is on." when it is; systemd's own prompt text,
small, near the field; and the unit being started at the foot. After the
unlock the page reads "Disk unlocked." until the greeter takes over.
Shutdown and restart show their own page in the same look.

Secondary text uses the higher-contrast tokens. The build (and every print
of a published look) fails if any text pairing falls below 4.5:1, or 7:1 for
the main text; the color itself is kept readable by `looks.py`.

## Following the look without a rebuild

The desktop's selection lives in the encrypted home, and a copy in `/var/lib`
sits on the same encrypted disk, so the boot can't read either. The look
reaches the boot partition instead (`followLook`, on by default):

1. Settings writes the owner's selection. Themeport's root bridge
   (`azure-folio-greeter-state`) rebuilds `/var/lib/azure-folio/appearance.json`
   from it, as it does for the greeter.
2. `interstellar-boot-look.path` watches that root-owned file and starts
   `interstellar-boot-look.service`. The service reads only that file:
   a small regular file, owned and writable by root alone, never through a
   symlink. From it, it keeps four values, each checked against the
   closed sets of `looks.py`: a known theme, light or dark, a named color of
   that theme or exactly `#rrggbb`, and the sky (orbit, prism, glow or haze;
   orbit when the file has none). Anything else is refused, and the boot partition
   keeps its last look. No password is involved, and nothing else
   crosses into the boot files.
3. It prints that look with the same `build.py` the system build uses,
   in a private temporary directory. It packs the theme as a small
   deterministic initrd archive with a manifest of SHA-256 sums, the manifest's
   own checksum last. It replaces `/boot/EFI/interstellar/look.cpio`
   atomically (temporary file, fsync, rename, fsync). The service runs
   sandboxed: no network, no home, no capabilities, a read-only system except
   that directory, its state directory and `/run/interstellar`.
4. The default boot entry lists `initrd /EFI/interstellar/look.cpio` after
   NixOS's initrd. systemd-boot loads both and the kernel unpacks them in
   order. The look lands in `/etc/interstellar/boot-look`, a path NixOS's
   initrd does not have, so nothing of NixOS's is replaced or written through.
5. In the initrd, `interstellar-boot-look-check.service` runs before Plymouth.
   It shows the archive's look only if the manifest's checksum, the manifest
   and every file in it check out, with plain file names and both theme files
   present. Then it copies the look to
   `/run/interstellar/themes/interstellar-look`. Plymouth's configuration
   asks for that theme first and falls back to the built-in `interstellar`
   theme (`plymouthd.defaults`) when it is not there.

So the next boot, and the shutdown page, show the look the owner chose. The
plate stays the one set below (`art`); a look changes theme, mode, color and
sky. These four values sit unencrypted on the boot partition, as approved.

### Why it can't block the unlock

- **No look published, or a bridge older than the looks**: the file is empty.
  systemd-boot skips empty initrd files, so the built-in look shows.
- **A file cut short, damaged, random, or of another format**: the kernel
  unpacks what it can, or stops at a bad header ("Initramfs unpacking
  failed"), after NixOS's initrd is already in place. The check finds the
  manifest missing or a checksum wrong and leaves Plymouth on the built-in
  look. Plymouth never sees a partial theme. This matters because a script
  theme that fails to parse shows a blank page while still taking keys.
  Every refusal exits 0, the check has a 10 s timeout, and Plymouth starts
  after it either way. If the check itself is missing, Plymouth does not find
  the look and uses the built-in one. On the next start (it runs at every
  boot), the service puts the published look back.
- **A missing file** would stop systemd-boot at any entry that names it
  ("Error preparing initrd"). The file always exists before an entry names
  it: the boot loader installer creates it (empty) when it is missing, then
  adds the line. The service only ever replaces it by rename. Only the
  default generation (and its specialisations) names it. Every older
  generation stays exactly as NixOS wrote it, so choosing the previous
  generation at the boot menu never depends on this file.
- **Plymouth off for one boot** (`plymouth.enable=0`, below) still works:
  the look is just an unused archive then.

To stop following the look and always show the built-in one:
`mariano.folio.boot.followLook = false;`.

## The built-in look

Shown until a look has been published, and whenever the published one is
missing or damaged. The defaults are Folio, night paper, azure ink and
Doré's *Nightfall*. A night page follows the firmware's black screen without
a flash of paper, in a dark room or in the KVM's capture.

```nix
mariano.folio.boot = {
  enable = true;
  theme = "folio";         # or "lumen"
  mode = "dark";           # or "light"
  ink = "azure";           # Folio: azure | cobalt | slate | "#rrggbb"
  accent = "blue";         # Lumen: one of its nine colors | "#rrggbb"
  sky = "orbit";           # Lumen: orbit | prism | glow | haze
  art = "dore-nightfall";  # any id in assets/azure-folio/catalog.json
};
```

## The remote unlock path (the Comet)

Nothing on the KVM path changes surface:

- Bonhart's initrd has no GPU driver, because amdgpu loads after the switch to
  the real root. The prompt is drawn on the firmware framebuffer (simpledrm,
  1920x1200 here), the same surface the text prompt uses now. The theme sets
  Plymouth's `UseSimpledrm=1` so the page appears at once. Without it, Plymouth
  ignores that framebuffer for 8 seconds. Whatever reaches the HDMI output
  before Linux reaches it now as well. This change does not add amdgpu to the
  initrd. The art is printed for 1920x1200 and for 1920x1080, the usual mode a
  KVM capture asks for.
- Keys from the Comet arrive as a USB keyboard. The initrd has no XKB data, so
  Plymouth reads them through the console with the same `us` keymap as today.
  A passphrase means the same keystrokes as before.
- The initrd type doesn't change. Bonhart already uses the systemd initrd, and
  the module refuses to build without it. Plymouth answers systemd's password
  request through `systemd-ask-password-plymouth`. If Plymouth is not running,
  the console agent asks as before.
- **Esc** switches to the boot messages, with the prompt still accepting input.
  Esc again returns to the page.
- To skip Plymouth for one boot, press `e` on the boot entry in the boot menu
  and add `plymouth.enable=0`. The menu waits 2 seconds.
- What happens after three refused passphrases is still up to systemd, as
  today. Its emergency path quits Plymouth before it writes to the console.
  This was not tried in the VM.
- Plymouth moves into the real root before the switch and redraws the page
  when amdgpu replaces the firmware framebuffer. A published look is read
  again from `/run`, which survives the switch. The built-in look is read from
  the initrd's copy of the theme, which the system now keeps in its closure
  so a garbage collection cannot remove it.

## Trying it in person

1. Pull, then run `sudo nixos-rebuild boot --flake /etc/nixos#bonhart`. Use
   `boot`, not `switch`: Plymouth only matters at the next start, and `boot`
   leaves the running system alone. The installer creates
   `/boot/EFI/interstellar/look.cpio` (empty) and adds it to the new default
   entry.
2. Reboot with the Comet connected and watch both the panel and the Comet's
   view. On this first boot, the built-in look shows. Once logged in,
   `systemctl status interstellar-boot-look` should report the look it wrote
   (`journalctl -u interstellar-boot-look`).
3. Change the look in Settings (for example Lumen, light), wait a few seconds,
   and reboot. Check that the page appears in that look before the prompt is
   needed and that typing prints dots. Type a wrong passphrase once and check
   the "Try again" message. Press Esc and Esc again, then unlock.
4. Close the lid, or use the "Hibernate" action, so that Bonhart resumes
   through the prompt. Unlock and confirm that the session comes back.
5. Try once with the lid in the position it will be left in, as the departure
   checklist in `docs/remote-workstation.md` asks.

**Roll back:** for a single boot, add `plymouth.enable=0` at the boot menu
(`e`), or choose the previous generation, whose entry does not load the look.
To keep the boot screen but drop the published look, set
`mariano.folio.boot.followLook = false;` and run `sudo nixos-rebuild boot`.
To return to the previous system, `sudo nixos-rebuild switch --rollback`
once logged in. `/boot/EFI/interstellar` can stay; nothing loads it then.

## Cost when on

- The initrd grows by about 8 MB, to 36 MB (Plymouth, pango/cairo, the theme
  and five font files). The published look adds a second archive of about
  0.3 MB (Folio) or 2.5 to 3.5 MB (Lumen: its film grain does not compress)
  on the boot partition, and the same in `/run` (RAM) while the system runs,
  for the shutdown page.
- Printing a look takes about two seconds of one core, in the background
  (a Lumen sky alone, under one: numpy computes it as the shader does):
  when theme, mode, color or sky change, when a new system prints differently, or
  when the file on the boot partition (or its copy in `/run`) is not the one
  it last wrote. Otherwise the service only compares and exits.
- Kernel parameters gain `quiet splash rd.udev.log_level=3 udev.log_level=3
  rd.systemd.show_status=auto`, and the console log level drops from 4 to 3.
  Errors still print, and Esc shows the rest.

## What has been verified

From the sources Bonhart runs (2026-10-31):

- systemd-boot 260.2 (`initrd_prepare`) loads every `initrd` line of an
  entry in order. It fails the entry when a file is missing, skips a 0-byte
  file, and pads each initrd but the last to 4 bytes. Bonhart's initrd is
  36,052,378 bytes, not a multiple of 4, so the padding is what lets the
  kernel find the archive after it.
- Kernel 6.18 (`init/initramfs.c`) unpacks archives in order. Before each
  entry it removes an existing path of another type (so a file or directory
  replaces a symlink there), and it follows symlinks in the parent path. A
  truncated plain archive raises no error, and a bad header stops unpacking
  with "Initramfs unpacking failed".
- Plymouth 26.134 tries `/run/plymouth/themes`, then the configured
  `ThemeDir`, then its own path, and falls back to `plymouthd.defaults` when
  the theme is not found. A script that fails to parse still "shows",
  blank. Before the switch to the real root it moves into `/sysroot`, so
  `/run` (moved by systemd) stays visible to it.

In builds and VMs only (2026-10-30/31):

- Bonhart's full system builds. Its initrd holds the check, bash and
  coreutils, `plymouthd.conf` with `Theme=interstellar-look` and
  `ThemeDir=/run/interstellar/themes`, and `plymouthd.defaults` with the
  built-in `interstellar`. Its boot installer runs the hook after NixOS's
  builder. The built-in Folio default prints byte for byte the same images as
  before. The unit tests pass (24).
- Lumen's skies against the shell (2026-10-31): each style and mode drawn by
  the shell's wallpaper in `scripts/folio-harness` and by `build.py`, at
  1920x1200 with the blue accent. In every pair at least 82 % of pixels are
  identical, 99 % are within one level, and with the grain averaged over 8x8
  pixels the two differ by under 0.1 level on average and 0.6 at most. The
  few pixels further apart are grain pixels whose hash rounds differently
  on the GPU.
- A UEFI VM booted as Bonhart does: systemd-boot, kernel 6.18, a zstd initrd
  after the AMD microcode archive, LUKS root, 1920x1200. The installer
  created the empty `look.cpio` and added it to the default entry only. With
  it empty, the built-in look showed. Then, seven times: `azure-folio publish`
  wrote appearance.json, the service printed the look to the boot partition
  under its sandbox, and the next boot's check reported "showing the look on
  the boot partition". The looks were Folio light with a custom `#8a2be2`,
  Folio dark cobalt, Lumen dark blue with prism, Lumen light with a custom
  `#ff6a00` and orbit, Lumen dark with a custom `#00c49a` and glow, Lumen
  dark purple with haze, and Lumen dark blue with orbit. Each prompt accepted
  the passphrase. In Lumen: a wrong passphrase showed the retry line, Esc
  showed the boot messages and returned, and the Caps Lock warning appeared.
- A cut at half the file, a cut at the manifest's checksum, a flipped byte
  and 64 KiB of random data each booted to the built-in look with a working
  prompt. The check reported incomplete, manifest, checksum, and "no look"
  respectively; for the random file, the kernel logged "invalid magic". Each
  time the service put the published look back at once.
- The probe archive showed the kernel's symlink handling in the initrd. A
  file under a symlinked directory was written into the store copy behind
  it. A file entry replaced a symlinked file. A directory entry replaced a
  symlinked directory with an empty one. That is why the look only adds its
  own directory.
- After that, powering off showed the shutdown page in the published look,
  from its copy in `/run`.
- Built-in Lumen, light, at 1920x1080 (the KVM's mode, so the 1080 print;
  run before the skies replaced the nebula), and the built-in Folio default
  at 1920x1200. Each run went through a wrong
  passphrase, Esc to the boot messages and back, Caps Lock, the passphrase
  `Folio-unlock#26` and power-off. After the unlock, the page read "Disk
  unlocked." across the VM's GPU driver taking over from the firmware
  framebuffer. OCR reads every line of the Lumen page.
- The boot messages behind Esc are readable in both modes. Before this,
  the theme wrote its console colors with six hex digits where Plymouth reads
  `0xRRGGBBAA`: cyan text on night paper, and nearly invisible text on a light
  page.
- Earlier (2026-10-29, Folio only): unlocking through the page after
  hibernation with Bonhart's LUKS, LVM root and swap layout; the passphrase
  `Folio-unlock#26` with shifted characters; 1920x1080.
- Not tested: the real panel and HDMI path through the Comet, amdgpu taking
  over from simpledrm after the unlock (a VM has no amdgpu), the greeter
  handover on Bonhart, and the service on Bonhart's own boot partition.

## Previewing without rebooting

`packages/plymouth-folio/preview.nix` boots a UEFI VM whose root is on LUKS,
through systemd-boot and the systemd initrd with this module on, as Bonhart
does (kernel 6.18, zstd initrd after the AMD microcode archive). It drives the
prompt with keystrokes and saves screenshots. It never touches the running
system:

```sh
nix build --impure -f packages/plymouth-folio/preview.nix -L          # built-in look, dark, 1920x1200
nix build --impure -f packages/plymouth-folio/preview.nix --argstr theme lumen --argstr sky glow -o result-lumen
nix build --impure -f packages/plymouth-folio/preview.nix --arg looks true -o result-looks   # the published-look path
ls result/   # *.png
```

The unit tests (validation, the archive, and the initrd check against
archives cut short or damaged the way the kernel unpacks them) are a flake
check: `nix build "path:.#checks.x86_64-linux.interstellar-boot" -L`.
