# ackerman boots m1n1 payloads, not UEFI: macOS's boot object is the A/B m1n1 stage-1, which
# loads /boot/m1n1/boot.bin from the ESP (p4, label OMARCHY) and, after an unclean boot, tries
# boot.bin.prev first. Every switch/boot writes the new generation's payload to boot.bin as a
# self-test (packages/ackerman-payload.py); ackerman-selftest.service then promotes it, or puts
# boot.bin.prev back and reboots when the network isn't up 90 s after network-online. There is
# no boot menu: older generations are reached with `nixos-rebuild switch --rollback`, or by
# booting boot.bin.prev.
{
  config,
  lib,
  pkgs,
  ackerman-private,
  ...
}:

let
  cfg = config.ackerman.payload;
  # A copy, so the system's closure holds this one file and not the whole private input
  m1n1 = pkgs.runCommand cfg.m1n1Name { } ''
    install -Dm644 ${ackerman-private}/nixos/m1n1/${cfg.m1n1Name}.bin $out
  '';
  payload = pkgs.runCommand "ackerman-payload" { buildInputs = [ pkgs.python3 ]; } ''
    install -Dm755 ${./packages/ackerman-payload.py} $out/bin/ackerman-payload
    substituteInPlace $out/bin/ackerman-payload --replace-fail "@m1n1@" "${m1n1}" \
      --replace-fail "@chosen@" ${lib.escapeShellArg (lib.concatStringsSep " " cfg.chosen)}
    patchShebangs --host $out/bin/ackerman-payload
  '';

  # m5pro-linux's self-revert, after the unlock (stage 2 starts only once the root is open)
  selftest = pkgs.writeShellApplication {
    name = "ackerman-selftest";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
      iputils
      util-linux
      systemd
      payload
    ];
    text = ''
      sleep 90
      if ip route get 1.1.1.1 >/dev/null 2>&1 && ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
        echo "network OK: keeping this generation"
        if grep -qw m5.hold=1 /proc/cmdline; then
          echo "held (m5.hold=1): not promoting; check the desktop, then run ackerman-payload promote"
          exit 0
        fi
        ackerman-payload promote
        exit 0
      fi
      mountpoint -q /boot || ls /boot >/dev/null
      G=/boot/r1-logs/.reverted-once
      if [ -e "$G" ]; then
        echo "network down again after a revert: NOT reverting a second time ($G); staying up"
        D=/boot/r1-logs/selftest-$(date +%Y%m%d-%H%M)-noloop; mkdir -p "$D"
        dmesg > "$D/dmesg.txt"; ip -br link > "$D/links.txt"; sync; exit 0
      fi
      mkdir -p /boot/r1-logs; touch "$G"
      D=/boot/r1-logs/selftest-$(date +%Y%m%d-%H%M); mkdir -p "$D"
      dmesg > "$D/dmesg.txt"; journalctl -b --no-pager > "$D/journal.txt" 2>&1; ip -br link > "$D/links.txt"
      cat /proc/cmdline > "$D/cmdline.txt"
      sha256sum /boot/m1n1/boot.bin > "$D/boot.bin.failed.sha256"
      cp /boot/m1n1/boot.bin.prev /boot/m1n1/boot.bin && sync && echo "reverted to boot.bin.prev" > "$D/REVERTED"
      sync
      systemctl reboot
    '';
  };
in
{
  options.ackerman.payload = {
    m1n1Name = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "m1n1-stage2-n1warm-gpu";
      description = ''
        The m1n1 stage-2 every payload starts with: nixos/m1n1/NAME.bin in the private input
        (exactly 0x420000 bytes; ackerman-payload checks).
      '';
    };
    chosen = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9,._-]+=[A-Za-z0-9,._-]*");
      default = [ ];
      example = [ "m5,t6050-display=1" ];
      description = ''
        m1n1 variables every payload carries on top of the fixed ones (show-notch, the N1, the GPU),
        as KEY=VALUE. A payload variant can add or drop one (ackerman-payload build --chosen,
        --no-chosen), and a promote keeps the booted payload's.
      '';
    };
    afterInstall = lib.mkOption {
      type = lib.types.lines;
      default = "";
      internal = true;
      description = ''
        Shell lines the boot-loader hook runs after the payload install succeeded ($1 is the
        toplevel); uboot.nix's systemd-boot entries.
      '';
    };
  };

  config = {
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = false;
    boot.loader.external = {
      enable = true;
      installHook = pkgs.writeShellScript "ackerman-install-payload" (
        if cfg.afterInstall == "" then
          ''
            exec ${payload}/bin/ackerman-payload install "$1"
          ''
        else
          ''
            ${payload}/bin/ackerman-payload install "$1" || exit $?
            ${cfg.afterInstall}
          ''
      );
    };
    # The payload builder appends the initrd secrets (the initrd SSH host key) itself.
    boot.loader.supportsInitrdSecrets = true;

    environment.systemPackages = [ payload ];

    systemd.services.ackerman-selftest = {
      description = "ackerman: self-reverting test boot (m5.selftest=1)";
      unitConfig.ConditionKernelCommandLine = "m5.selftest=1";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # Once per boot: a switch must not run it again (2026-11-08 22:08, a switch restarted
      # wait-online, the self-test ran again and promoted the booted generation over the new one).
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe selftest;
      };
    };
  };
}
