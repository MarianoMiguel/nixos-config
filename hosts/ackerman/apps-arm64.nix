# bonhart's apps that have official arm64 Linux builds but no aarch64 package in nixpkgs or in
# apps.nix (parity groups 2 and 3a of m5max-linux builds/private/parity-bonhart-ackerman.md):
# herdr, Paper, ONLYOFFICE and CodexBar's CLI, repackaged here from their vendors' arm64 releases
# (hosts/ackerman/packages/arm64/, each a pinned download with its hash), and LibrePods, built from
# source. Beeper and Granola need nothing here: packages/beeper.nix now picks the arm64 AppImage of
# the same release and Granola lists aarch64, so apps.nix installs them on ackerman as on bonhart.
# Obsidian and Codex Desktop come from apps.nix too (bigApps).
#
# Off switches: ackerman.arm64Apps.enable = false drops the four repackaged apps; LibrePods follows
# mariano.bigApps.enable (off in ackerman-core), as the source builds do.
{
  config,
  lib,
  pkgs,
  librepods-rust,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # As bonhart's gnome.nix: the Rust package installs only its binary
  librepods = librepods-rust.packages.${system}.default;
  librepodsDesktopItem = pkgs.makeDesktopItem {
    name = "librepods";
    desktopName = "LibrePods";
    genericName = "AirPods Controls";
    comment = "Control AirPods features from Linux";
    exec = "${librepods}/bin/librepods";
    icon = "${librepods-rust}/linux-rust/assets/icon.png";
    categories = [ "Utility" ];
    keywords = [
      "AirPods"
      "Bluetooth"
      "Headphones"
    ];
    startupNotify = true;
    startupWMClass = "librepods";
  };
  # LibrePods lives in the tray: DMS's (Quickshell's StatusNotifierWatcher) here, GNOME's
  # AppIndicator on bonhart
  waitForStatusNotifierWatcher = pkgs.writeShellScript "wait-for-status-notifier-watcher" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 300); do
      if ${pkgs.systemd}/bin/busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    echo "Timed out waiting for org.kde.StatusNotifierWatcher" >&2
    exit 1
  '';
in
{
  options.ackerman.arm64Apps.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install the vendors' arm64 builds repackaged for ackerman: herdr, Paper, ONLYOFFICE and
      CodexBar's CLI.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf config.ackerman.arm64Apps.enable {
      environment.systemPackages = [
        (pkgs.callPackage ./packages/arm64/herdr.nix { })
        (pkgs.callPackage ./packages/arm64/paper-desktop.nix { })
        (pkgs.callPackage ./packages/arm64/onlyoffice.nix { })
        (pkgs.callPackage ./packages/arm64/codexbar.nix { })
      ];
    })

    # LibrePods, as bonhart runs it (gnome.nix): in the tray from login on
    (lib.mkIf config.mariano.bigApps.enable {
      environment.systemPackages = [
        librepods
        librepodsDesktopItem
      ];
      systemd.user.tmpfiles.rules = [
        "d %h/.config/librepods 0700 - -"
        "d %h/.local/share/librepods 0700 - -"
        "f %h/.local/share/librepods/devices.json 0600 - - - {}"
      ];
      systemd.user.services.librepods = {
        description = "LibrePods AirPods integration";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStartPre = waitForStatusNotifierWatcher;
          ExecStart = "${librepods}/bin/librepods --start-minimized";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
    })
  ];
}
