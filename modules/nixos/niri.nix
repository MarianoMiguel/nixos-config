{ cat-dms, codeIsland-dms, dms, dms-codexbar, pkgs, quickshell, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  codexbar = pkgs.stdenvNoCC.mkDerivation {
    pname = "codexbar";
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

  environment.systemPackages = with pkgs; [
    brightnessctl
    libnotify
    playerctl
    swayidle
    swaylock
    wl-kbptr
    wtype
    xwayland-satellite
    codexbar
    codeIslandLinux
  ];

  systemd.user.services = {
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
