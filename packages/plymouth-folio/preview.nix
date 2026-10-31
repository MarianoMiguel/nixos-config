# Preview Interstellar's boot screen without rebooting anything: a UEFI VM
# whose root is on LUKS boots through systemd-boot and the systemd initrd
# with mariano.folio.boot on, as Bonhart does (kernel 6.18, zstd initrd with
# the AMD microcode archive in front), and the test types into the Plymouth
# prompt (a wrong passphrase, Esc and back, Caps Lock, the right one) and
# saves screenshots. Then it powers off to show the shutdown page.
# docs/folio-boot.md has the commands.
#
#   nix build --impure -f packages/plymouth-folio/preview.nix -L
#   nix build --impure -f packages/plymouth-folio/preview.nix --argstr theme lumen --argstr mode light -o result-lumen
#
# The VM's stdvga advertises the given mode in its EDID so OVMF (and
# simpledrm in the initrd) comes up at Bonhart's firmware size.
{
  mode ? "dark",
  theme ? "folio",
  xres ? 1920,
  yres ? 1200,
  # Plymouth's debug trace on the serial console (in the build log).
  debug ? false,
}:
let
  # The flake's own nixpkgs, from flake.lock (no copy of the checkout).
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  nixpkgs = builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  passphrase = "Folio-unlock#26";
in
pkgs.testers.runNixOSTest {
  name = "interstellar-boot-${theme}-${mode}-${toString xres}x${toString yres}";
  enableOCR = true;

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../../modules/nixos/folio-boot.nix ];
      networking.hostName = "bonhart";
      virtualisation = {
        emptyDiskImages = [ 1024 ];
        useBootLoader = true;
        mountHostNixStore = true;
        useEFIBoot = true;
        memorySize = 2048;
        cores = 2;
        qemu.options = [
          "-vga none"
          "-device VGA,edid=on,xres=${toString xres},yres=${toString yres}"
        ];
      };
      # As Bonhart: kernel series, systemd-boot, zstd initrd with the AMD
      # microcode archive prepended.
      boot.kernelPackages = pkgs.linuxPackages_6_18;
      hardware.cpu.amd.updateMicrocode = true;
      boot.loader.systemd-boot.enable = true;
      boot.loader.timeout = 1;
      boot.initrd.systemd.enable = true;
      environment.systemPackages = [ pkgs.cryptsetup ];

      specialisation.luks.configuration = {
        boot.initrd.luks.devices = lib.mkVMOverride {
          nixos-crypt.device = "/dev/vdb";
        };
        virtualisation.rootDevice = "/dev/mapper/nixos-crypt";
        mariano.folio.boot = {
          enable = true;
          inherit theme mode;
        };
        # The test VM has a serial console; Plymouth would show text there
        # (and everywhere) unless told to ignore it. Bonhart has none.
        boot.kernelParams = [
          "plymouth.ignore-serial-consoles"
        ]
        ++ lib.optional debug "plymouth.debug=stream:/dev/ttyS0";
      };
    };

  testScript =
    { nodes, ... }:
    let
      luks = nodes.machine.specialisation.luks.configuration.system.build.toplevel;
    in
    ''
      import time

      def ocr(label):
          # OCR as a readability check only; waits follow the serial log.
          try:
              text = " | ".join(l.strip() for l in machine.get_screen_text().splitlines() if l.strip())
              print(f"OCR {label}: {text[:500]}")
          except Exception as e:
              print(f"OCR {label} failed: {e}")

      machine.wait_for_unit("multi-user.target")
      machine.succeed("echo -n '${passphrase}' | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
      machine.succeed("echo -n '${passphrase}' | cryptsetup luksOpen -q /dev/vdb nixos-crypt")
      machine.succeed("mkfs.ext4 -q /dev/mapper/nixos-crypt")
      machine.succeed("${luks}/bin/switch-to-configuration boot")
      # Make the specialisation the default boot entry.
      entry = machine.succeed("ls /boot/loader/entries | grep specialisation-luks").strip()
      machine.succeed(f"sed -i 's/^default .*/default {entry}/' /boot/loader/loader.conf")
      print(machine.succeed("cat /boot/loader/loader.conf"))
      machine.succeed("sync")
      machine.crash()

      machine.start()
      machine.wait_for_console_text("Started Forward Password Requests to Plymouth\\.")
      time.sleep(3)
      machine.screenshot("01-prompt")
      ocr("prompt")

      machine.send_chars("wrong-pass")
      time.sleep(1)
      machine.screenshot("02-typing")
      machine.send_key("ret")
      time.sleep(0.4)
      machine.screenshot("03-checking")
      machine.wait_for_console_text("Failed to activate with specified passphrase")
      time.sleep(3)
      machine.screenshot("04-retry")
      ocr("retry")

      # Esc: the boot messages, with the prompt; Esc again: the page.
      machine.send_key("esc")
      time.sleep(2)
      machine.screenshot("05-messages")
      machine.send_key("esc")
      time.sleep(2)
      machine.screenshot("06-back")

      # Caps Lock warning, then a passphrase with shifted symbols (US layout).
      machine.send_key("caps_lock")
      time.sleep(1)
      machine.screenshot("07-caps")
      machine.send_key("caps_lock")
      time.sleep(0.5)
      machine.send_chars("${passphrase}")
      time.sleep(0.5)
      machine.screenshot("08-typed")
      machine.send_key("ret")
      for i in range(6):
          time.sleep(0.5)
          machine.screenshot(f"09-after-{i}")

      machine.wait_for_unit("multi-user.target")
      assert "/dev/mapper/nixos-crypt on / " in machine.succeed("mount")

      # The shutdown page.
      machine.execute("systemctl poweroff --no-block")
      for i in range(8):
          time.sleep(0.15)
          try:
              machine.screenshot(f"10-poweroff-{i}")
          except Exception:
              break  # the VM is already off
      try:
          machine.wait_for_shutdown()
      except Exception:
          pass
    '';
}
