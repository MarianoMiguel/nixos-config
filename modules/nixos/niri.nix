{ cat-dms, codeIsland-dms, dms, dms-codexbar, librepods-rust, pkgs, quickshell, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  librepods = librepods-rust.packages.${system}.default;
  # The Rust package currently installs only its binary even though upstream
  # ships a desktop entry and icon. Provide the missing launcher so LibrePods
  # appears in GNOME's application grid as well as Niri's launchers.
  librepodsDesktopItem = pkgs.makeDesktopItem {
    # iced publishes this exact value as the Wayland application ID. GNOME
    # matches Wayland windows to the desktop-file basename for dock icons.
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
  codexbarUnwrapped = pkgs.stdenvNoCC.mkDerivation {
    pname = "codexbar-unwrapped";
    version = "0.28.0";

    src = pkgs.fetchzip {
      url = "https://github.com/steipete/CodexBar/releases/download/v0.28.0/CodexBarCLI-v0.28.0-linux-x86_64.tar.gz";
      sha256 = "1mh17kkv11piif7yir4fkn5ggmp681ify5fp22447n4lg7q4jn1i";
      stripRoot = false;
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = with pkgs; [
      curl
      sqlite
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm0755 codexbar "$out/bin/codexbar"
      install -Dm0755 CodexBarCLI "$out/bin/CodexBarCLI"
      runHook postInstall
    '';
  };

  # codexbar reports the provider CLI versions by shelling out to `which codex`,
  # and aborts on an illegal instruction rather than reporting an error when
  # that lookup comes back empty. Both provider CLIs install themselves into
  # ~/.local/bin, which is outside the system profile that the DMS service is
  # limited to, so the bar plugin crashed on every refresh while the same
  # command succeeded from an interactive shell. Put that directory back on the
  # path for every caller of this binary.
  codexbar = pkgs.symlinkJoin {
    name = "codexbar-${codexbarUnwrapped.version}";
    paths = [ codexbarUnwrapped ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for binary in codexbar CodexBarCLI; do
        rm "$out/bin/$binary"
        makeWrapper "${codexbarUnwrapped}/bin/$binary" "$out/bin/$binary" \
          --run 'export PATH="$HOME/.local/bin:$PATH"'
      done
    '';
  };

  codeIslandLinux = pkgs.stdenvNoCC.mkDerivation {
    pname = "codeisland-linux";
    version = "0.1.0";

    src = codeIsland-dms;

    installPhase = ''
      runHook preInstall
      install -d "$out/share/codeisland-linux"
      cp -R linux-skeleton/codeisland_linux "$out/share/codeisland-linux/"

      install -d "$out/bin"
      for module in server fixture subscriber opencode_adapter opencode_plugin codex_adapter codex_hook claude_adapter claude_hook; do
        cat > "$out/bin/codeisland-$module" <<EOF
#!/bin/sh
export PYTHONPATH="$out/share/codeisland-linux''${PYTHONPATH:+:$PYTHONPATH}"
exec ${pkgs.python3}/bin/python -m codeisland_linux.$module "\$@"
EOF
        chmod 0755 "$out/bin/codeisland-$module"
      done
      runHook postInstall
    '';
  };
in

{
  programs.niri.enable = true;

  # Keep the compositor and shell responsive when builds or AI agents saturate
  # the CPU. CPUWeight only changes scheduling under contention.
  systemd.user.services.niri.serviceConfig.CPUWeight = 250;

  programs.dank-material-shell = {
    enable = true;
    package = dms.packages.${system}.dms-shell;
    quickshell.package = quickshell.packages.${system}.default;
    plugins = {
      codexBar = {
        src = dms-codexbar;
        settings = {
          enabled = true;
          codexbarPath = "${codexbar}/bin/codexbar";
          refreshInterval = "120000";
          sourceMode = "oauth";
        };
      };
      catWidget = {
        src = cat-dms;
        settings.enabled = true;
      };
      codeIsland = {
        src = codeIsland-dms;
        settings.enabled = true;
      };
    };

    # dgop is not available in the current nixpkgs pin.
    enableSystemMonitoring = false;

    # The niri session starts DMS through the checked-in niri config. Keeping
    # the service disabled avoids starting the shell inside Plasma sessions.
    systemd.enable = false;
  };

  services.iio-niri.enable = false;

  # LibrePods exposes its background controls through StatusNotifier. DMS
  # provides that interface in Niri; GNOME needs its AppIndicator extension.
  home-manager.users.mariano.programs.gnome-shell = {
    enable = true;
    extensions = [
      { package = pkgs.gnomeExtensions.appindicator; }
    ];
  };

  environment.systemPackages = with pkgs; [
    brightnessctl
    librepods
    librepodsDesktopItem
    libnotify
    playerctl
    swayidle
    swaylock
    wl-kbptr
    wl-mirror
    wtype
    xwayland-satellite
    codexbar
    codeIslandLinux
  ];

  systemd.user.tmpfiles.rules = [
    "d %h/.config/librepods 0700 - -"
    "d %h/.local/share/librepods 0700 - -"
    "f %h/.local/share/librepods/devices.json 0600 - - - {}"
  ];

  systemd.user.services = {
    dms = {
      overrideStrategy = "asDropin";
      # Defining a NixOS-managed drop-in gives the service a restricted PATH.
      # DMS launches Quickshell and helper tools by executable name, so retain
      # the active system path that was available before this override.
      path = [ "/run/current-system/sw" ];
      serviceConfig.CPUWeight = 150;
    };

    librepods = {
      description = "LibrePods AirPods integration";
      partOf = [ "graphical-session.target" ];
      wants = [ "dms.service" ];
      after = [ "dms.service" ];
      unitConfig.ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
      serviceConfig = {
        ExecStartPre = waitForStatusNotifierWatcher;
        ExecStart = "${librepods}/bin/librepods --start-minimized";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    codeislandd = {
      description = "CodeIsland daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${codeIslandLinux}/bin/codeisland-server";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    codeisland-codex-adapter = {
      description = "CodeIsland Codex adapter";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "codeislandd.service" ];
      serviceConfig = {
        ExecStart = "${codeIslandLinux}/bin/codeisland-codex_adapter --watch";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    codeisland-claude-adapter = {
      description = "CodeIsland Claude Code adapter";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "codeislandd.service" ];
      serviceConfig = {
        ExecStart = "${codeIslandLinux}/bin/codeisland-claude_adapter --watch";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
