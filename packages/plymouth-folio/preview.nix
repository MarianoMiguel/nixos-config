# Preview Interstellar's boot screen without rebooting anything: a UEFI VM
# whose root is on LUKS boots through systemd-boot and the systemd initrd
# with mariano.folio.boot on, as Bonhart does (kernel 6.18, zstd initrd with
# the AMD microcode archive in front), and the test types into the Plymouth
# prompt and saves screenshots. docs/folio-boot.md has the commands.
#
#   nix build --impure -f packages/plymouth-folio/preview.nix -L
#   nix build --impure -f packages/plymouth-folio/preview.nix --argstr mode light -o result-light
#   nix build --impure -f packages/plymouth-folio/preview.nix --arg looks true -o result-looks
#
# With `looks`, it walks the published-look path end to end: azure-folio's
# root bridge writes appearance.json, interstellar-boot-look prints the look
# onto the VM's boot partition, systemd-boot loads it after NixOS's initrd,
# and the initrd's check hands it to Plymouth. It boots every theme and
# mode, custom colors, an empty, a cut-short, a damaged and a random file,
# and a probe of how the kernel unpacks an archive over symlinked paths.
#
# The VM's stdvga advertises the given mode in its EDID so OVMF (and
# simpledrm in the initrd) comes up at Bonhart's firmware size.
{
  mode ? "dark",
  theme ? "folio",
  xres ? 1920,
  yres ? 1200,
  looks ? false,
  # Plymouth's debug trace on the serial console (in the build log).
  debug ? false,
}:
let
  # The flake's own nixpkgs, from flake.lock (no copy of the checkout).
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  nixpkgs = builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  passphrase = "Folio-unlock#26";
  azureFolio = pkgs.callPackage ../azure-folio.nix { };
  python = pkgs.python3.withPackages (p: [ p.pillow ]);

  # How the kernel unpacks an archive over paths NixOS's initrd holds as
  # symlinks into the store: a file under a symlinked directory, a file over
  # a symlinked file, a directory over a symlinked directory.
  probeDir = pkgs.runCommand "interstellar-probe-dir" { } ''
    mkdir "$out"; echo original > "$out/original"
  '';
  probeArchive = pkgs.runCommand "interstellar-probe.cpio" { nativeBuildInputs = [ python ]; } ''
    python3 - "$out" <<'EOF'
    import sys
    sys.path.insert(0, "${(pkgs.callPackage ./. { }).src}")
    import boot_look
    p = "etc/interstellar-probe"
    entries = [(f"{p}/dir-link/through", 0o100644, b"written through the symlink\n"),
               (f"{p}/file-link", 0o100644, b"replaced\n"),
               (f"{p}/dir-link-2", 0o40755, None)]
    open(sys.argv[1], "wb").write(boot_look.newc(entries))
    EOF
  '';

  # Published looks: azure-folio's selection, as the Settings app writes it.
  published = [
    {
      name = "folio-light-custom";
      selection = {
        theme = "folio";
        mode = "light";
        ink = "custom";
        customInk = "#8a2be2";
      };
      look = "folio light #8a2be2";
    }
    {
      name = "folio-dark-cobalt";
      selection = {
        theme = "folio";
        mode = "dark";
        ink = "cobalt";
      };
      look = "folio dark cobalt";
    }
    {
      name = "lumen-dark-blue";
      selection = {
        theme = "lumen";
        mode = "dark";
        accent = "blue";
      };
      look = "lumen dark blue";
      interact = true;
    }
    {
      name = "lumen-light-custom";
      selection = {
        theme = "lumen";
        mode = "light";
        accent = "custom";
        customAccent = "#ff6a00";
      };
      look = "lumen light #ff6a00";
    }
    {
      name = "lumen-dark-custom";
      selection = {
        theme = "lumen";
        mode = "dark";
        accent = "custom";
        customAccent = "#00c49a";
      };
      look = "lumen dark #00c49a";
    }
  ];
in
pkgs.testers.runNixOSTest {
  name = "interstellar-boot-${theme}-${mode}-${toString xres}x${toString yres}${pkgs.lib.optionalString looks "-looks"}";
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
      environment.systemPackages = [
        pkgs.cryptsetup
        azureFolio
      ];
      users.users.mariano = {
        isNormalUser = true;
        uid = 1000;
      };

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

        # The probe's symlinks, and what it finds after the kernel unpacked.
        boot.initrd.systemd.contents = lib.mkIf looks {
          "/etc/interstellar-probe/dir-link".source = probeDir;
          "/etc/interstellar-probe/dir-link-2".source = probeDir;
          "/etc/interstellar-probe/file-link".source = pkgs.writeText "interstellar-probe-file" "original\n";
        };
        boot.initrd.systemd.services.interstellar-probe = lib.mkIf looks {
          wantedBy = [ "initrd.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          script = ''
            cd /etc/interstellar-probe
            for p in dir-link dir-link/through dir-link/original file-link dir-link-2 dir-link-2/original; do
              if [ -e "$p" ] || [ -L "$p" ]; then
                echo "probe: $(stat -c '%N: %F' "$p")$( [ -f "$p" ] && printf ' = %s' "$(cat "$p")")"
              else
                echo "probe: '$p': absent"
              fi
            done
            echo "probe: dir-link resolves to $(readlink -f dir-link)"
          '';
        };
      };
    };

  testScript =
    { nodes, ... }:
    let
      luks = nodes.machine.specialisation.luks.configuration.system.build.toplevel;
    in
    ''
      import json, time

      def ocr(label):
          # OCR as a readability check only; waits follow the serial log.
          try:
              text = " | ".join(l.strip() for l in machine.get_screen_text().splitlines() if l.strip())
              print(f"OCR {label}: {text[:500]}")
          except Exception as e:
              print(f"OCR {label} failed: {e}")

      def boot_to_prompt(label):
          machine.succeed("sync")
          machine.crash()
          machine.start()
          machine.wait_for_console_text("Started Forward Password Requests to Plymouth\\.")
          time.sleep(3)
          machine.screenshot(f"{label}-prompt")
          ocr(label)

      def unlock(label):
          machine.send_chars("${passphrase}")
          time.sleep(0.5)
          machine.screenshot(f"{label}-typed")
          machine.send_key("ret")
          machine.wait_for_unit("multi-user.target")
          assert "/dev/mapper/nixos-crypt on / " in machine.succeed("mount")
          verdict = machine.succeed("journalctl -b -o cat -u interstellar-boot-look-check.service")
          print(f"CHECK {label}: {verdict.strip()}")
          return verdict

      machine.wait_for_unit("multi-user.target")
      machine.succeed("echo -n '${passphrase}' | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
      machine.succeed("echo -n '${passphrase}' | cryptsetup luksOpen -q /dev/vdb nixos-crypt")
      machine.succeed("mkfs.ext4 -q /dev/mapper/nixos-crypt")
      machine.succeed("${luks}/bin/switch-to-configuration boot")
      # Make the specialisation the default boot entry, then install again:
      # the installer adds the look to the default entry only.
      entry = machine.succeed("ls /boot/loader/entries | grep specialisation-luks").strip()
      machine.succeed(f"sed -i 's/^default .*/default {entry}/' /boot/loader/loader.conf")
      machine.succeed("${luks}/bin/switch-to-configuration boot")
      print(machine.succeed("cat /boot/loader/loader.conf; for f in /boot/loader/entries/*; do echo \"== $f\"; cat \"$f\"; done"))
      print(machine.succeed("ls -la /boot/EFI/interstellar"))
      ${
        if !looks then
          ''
            boot_to_prompt("01")

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
            poweroff = "10"
          ''
        else
          ''
            # The default entry names NixOS's initrd, then the look; an older
            # entry is left as NixOS wrote it.
            spec = machine.succeed(f"cat /boot/loader/entries/{entry}")
            lines = [l for l in spec.splitlines() if l.startswith("initrd ")]
            assert len(lines) == 2 and lines[1] == "initrd /EFI/interstellar/look.cpio", spec
            base = machine.succeed("cat /boot/loader/entries/nixos-generation-1.conf")
            assert "interstellar" not in base, base
            assert machine.succeed("stat -c %s /boot/EFI/interstellar/look.cpio").strip() == "0"

            # Nothing published yet: an empty file, the built-in look.
            boot_to_prompt("00-builtin-empty")
            assert "no look on the boot partition" in unlock("00-builtin-empty")

            def publish(selection, look):
                machine.succeed(
                    "install -d -m 0755 /var/lib/azure-folio",
                    "install -d -o mariano -m 0755 /home/mariano/.local/state/nixos-config/azure-folio",
                    f"echo '{json.dumps(selection)}' > /tmp/selection.json",
                    "install -o mariano -m 0644 /tmp/selection.json /home/mariano/.local/state/nixos-config/azure-folio/selection.json",
                    # What azure-folio-greeter-state.service runs.
                    "azure-folio publish --input /home/mariano/.local/state/nixos-config/azure-folio/selection.json --output /var/lib/azure-folio/appearance.json",
                )
                want = json.dumps(look.split(" "))
                machine.wait_until_succeeds(f"grep -qF '\"look\": {want}' /var/lib/interstellar-boot-look/published.json", timeout=180)
                print(machine.succeed("journalctl -b -o cat -u interstellar-boot-look.service | tail -n 3"))
                print(machine.succeed("ls -la /boot/EFI/interstellar /run/interstellar/themes/interstellar-look"))

            ${pkgs.lib.concatMapStrings (p: ''
              publish(${builtins.toJSON p.selection}, "${p.look}")
              boot_to_prompt("${p.name}")
              ${pkgs.lib.optionalString (p.interact or false) ''
                machine.send_chars("wrong-pass")
                time.sleep(1)
                machine.screenshot("${p.name}-typing")
                machine.send_key("ret")
                time.sleep(0.4)
                machine.screenshot("${p.name}-checking")
                machine.wait_for_console_text("Failed to activate with specified passphrase")
                time.sleep(3)
                machine.screenshot("${p.name}-retry")
                ocr("${p.name} retry")
                machine.send_key("esc")
                time.sleep(2)
                machine.screenshot("${p.name}-messages")
                machine.send_key("esc")
                time.sleep(2)
                machine.screenshot("${p.name}-back")
                machine.send_key("caps_lock")
                time.sleep(1)
                machine.screenshot("${p.name}-caps")
                machine.send_key("caps_lock")
                time.sleep(0.5)
              ''}
              assert "showing the look on the boot partition: ${p.look}" in unlock("${p.name}")
            '') published}

            # Damaged files on the boot partition: each boot shows the
            # built-in look, and the service puts the published look back.
            good = machine.succeed("sha256sum /boot/EFI/interstellar/look.cpio").split()[0]
            size = int(machine.succeed("stat -c %s /boot/EFI/interstellar/look.cpio"))
            damage = {
                "10-cut-short": f"head -c {size // 2} /boot/EFI/interstellar/look.cpio > /tmp/l && cp /tmp/l /boot/EFI/interstellar/look.cpio",
                "11-cut-before-checksum": f"head -c {size - 200} /boot/EFI/interstellar/look.cpio > /tmp/l && cp /tmp/l /boot/EFI/interstellar/look.cpio",
                "12-flipped-byte": f"printf '\\377' | dd of=/boot/EFI/interstellar/look.cpio bs=1 seek={size // 3} conv=notrunc",
                "13-random": "head -c 65536 /dev/urandom > /boot/EFI/interstellar/look.cpio",
            }
            for label, command in damage.items():
                machine.succeed(command, "sync")
                boot_to_prompt(label)
                verdict = unlock(label)
                assert "showing the look" not in verdict, verdict
                machine.succeed("systemctl start interstellar-boot-look.service")
                assert machine.succeed("sha256sum /boot/EFI/interstellar/look.cpio").split()[0] == good
                print(machine.succeed("dmesg | grep -i -E 'initramfs|unpack' || true"))

            # The probe: how the kernel unpacked over symlinks.
            machine.succeed("cp ${probeArchive} /boot/EFI/interstellar/look.cpio", "sync")
            boot_to_prompt("14-probe")
            unlock("14-probe")
            print(machine.succeed("journalctl -b -o cat -u interstellar-probe.service"))
            # The service has put the published look back, with its copy in
            # /run: the shutdown page shows it.
            machine.succeed("systemctl start interstellar-boot-look.service")
            assert machine.succeed("sha256sum /boot/EFI/interstellar/look.cpio").split()[0] == good
            print(machine.succeed("head -n 3 /run/interstellar/themes/interstellar-look/interstellar-look.script"))
            poweroff = "15"
          ''
      }

      # The shutdown page.
      machine.execute("systemctl poweroff --no-block")
      for i in range(8):
          time.sleep(0.15)
          try:
              machine.screenshot(f"{poweroff}-poweroff-{i}")
          except Exception:
              break  # the VM is already off
      try:
          machine.wait_for_shutdown()
      except Exception:
          pass
    '';
}
