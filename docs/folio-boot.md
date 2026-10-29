# Folio boot and disk-unlock screen

`mariano.folio.boot.enable` (in `modules/nixos/folio-boot.nix`, imported by
Bonhart) replaces the bare console LUKS prompt with Folio's page:
Plymouth with the `folio` theme (`packages/plymouth-folio`). It is **off**
until the owner has tried it in person. Off, the system builds exactly as
before: same initrd, kernel, kernel parameters and bootloader.

## What it shows

The lock screen's composition. On the left is the plate, printed at the screen's
exact pixel size. On the right is the paper page, with the machine's name tab
hanging from the top edge. When the disk asks for its passphrase:

- "Encrypted disk", then **Unlock Bonhart's disk**, a rule, and a well that
  prints one ink dot per typed character. The caret breathes while it waits.
  Past the well's width, the count appears.
- "Type the disk passphrase, then press Enter." Then "Checking the
  passphrase…". If the disk refuses, the well shakes and says "That
  passphrase didn't unlock the disk. Try again."
- "Caps Lock is on." when it is.
- systemd's own prompt text, small, under the hint.
- At the foot: "Esc · boot messages" and the unit being started.

After the unlock, the page reads "Starting Bonhart · Disk unlocked" until the
greeter takes over. Shutdown and restart show "Bonhart is shutting down" or
"Bonhart is restarting".

Paper, ink and plate are fixed when the system is built. The desktop's
light/dark selection lives in the encrypted home, so the boot can't read it,
and a copy in `/var/lib` sits on the same encrypted disk. The defaults are night
paper, azure ink and Doré's *Nightfall*. A night page follows the firmware's
black screen without a flash of paper, in a dark room or in the KVM's capture.
To change them:

```nix
mariano.folio.boot = {
  enable = true;
  mode = "light";          # or "dark"
  ink = "azure";           # azure | cobalt | slate
  art = "summer-sicily";   # any id in assets/azure-folio/catalog.json
};
```

Secondary text uses Folio's higher-contrast tokens. The build fails if any
text pairing falls below 4.5:1, or 7:1 for the main text.

## The remote unlock path (the Comet)

Nothing on the KVM path changes surface:

- Bonhart's initrd has no GPU driver, because amdgpu loads after the switch to
  the real root. The prompt is drawn on the firmware framebuffer (simpledrm,
  1920x1200 here), the same surface the text prompt uses now. The theme sets
  Plymouth's `UseSimpledrm=1` so the page appears at once. Without it, Plymouth
  ignores that framebuffer for 8 seconds. Whatever reaches the HDMI output
  before Linux reaches it now as well. This change does not add amdgpu to the
  initrd.
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

## Trying it in person

1. In `hosts/bonhart/common.nix` (or `local.nix`), set
   `mariano.folio.boot.enable = true;`, then run
   `sudo nixos-rebuild boot --flake /etc/nixos#bonhart`. Use `boot`, not
   `switch`: Plymouth only matters at the next start, and `boot` leaves the
   running system alone.
2. Reboot with the Comet connected and watch both the panel and the Comet's
   view. Check that the page appears before the prompt is needed and that
   typing prints dots. Type a wrong passphrase once and check the "Try again"
   message. Press Esc and Esc again, then unlock.
3. Close the lid, or use the "Hibernate" action, so that Bonhart resumes
   through the prompt. Unlock and confirm that the session comes back.
4. Try once with the lid in the position it will be left in, as the departure
   checklist in `docs/remote-workstation.md` asks.

**Roll back:** at the boot menu choose the previous generation, then remove
the line and run `sudo nixos-rebuild boot` (or
`sudo nixos-rebuild switch --rollback` once logged in). For a single boot,
`plymouth.enable=0` at the boot menu also works.

## Cost when on

- The initrd grows by about 8 MB, to 36 MB (Plymouth, pango/cairo, the theme
  and five font files). The ESP has plenty of room.
- Kernel parameters gain `quiet splash rd.udev.log_level=3 udev.log_level=3
  rd.systemd.show_status=auto`, and the console log level drops from 4 to 3.
  Errors still print, and Esc shows the rest.

## What has been verified (2026-10-29, builds and VMs only)

- With the option off, Bonhart's `system.build.toplevel` derivation is
  identical to the tree without this work. With it on, the full system builds.
  Only the initrd, the kernel parameters and the console log level change. The
  kernel and the bootloader installer stay the same, and the initrd stays
  systemd.
- The enabled initrd contains plymouthd, the script, pango and DRM plugins, the
  `folio` theme, the fonts, `UseSimpledrm=1` and the
  `systemd-ask-password-plymouth` agent. Bonhart's crypttab is unchanged.
- A UEFI VM with a 1920x1200 firmware framebuffer (and a second run at
  1920x1080), a LUKS root and the systemd initrd: Plymouth drew the page on
  simpledrm at once, and read keys through the console with the `us` keymap.
  A wrong passphrase was refused with the retry message. Esc showed the boot
  messages with the prompt still live, and Esc again returned to the page. The
  Caps Lock warning worked. The passphrase `Folio-unlock#26` (shifted
  characters, `-`, `#`) unlocked the disk. After the unlock the page showed
  "Starting Bonhart · Disk unlocked" across the VM's GPU driver taking over,
  and powering off showed the shutdown page. Light paper worked as well. OCR
  of the dark page reads every line, the systemd prompt included.
- The same with Bonhart's layout (LUKS, then LVM root and swap): hibernated,
  powered on, unlocked through the page, and the session image was restored.
- Not tested: the real panel and HDMI path through the Comet, amdgpu taking
  over from simpledrm after the unlock (a VM has no amdgpu), and the greeter
  handover on Bonhart.

## Previewing without rebooting

`packages/plymouth-folio/preview.nix` boots a UEFI VM whose root is on LUKS,
through the systemd initrd with this module on. It drives the prompt with
keystrokes and saves screenshots. It never touches the running system:

```sh
nix build --impure -f packages/plymouth-folio/preview.nix -L          # dark, 1920x1200
nix build --impure -f packages/plymouth-folio/preview.nix --argstr mode light -o result-light
ls result/   # *.png
```
