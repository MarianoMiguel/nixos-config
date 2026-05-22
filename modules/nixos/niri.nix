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
        settings = {
          enabled = true;
        };
      };
      codeIsland = {
        src = codeIsland-dms;
        settings = {
          enabled = true;
        };
      };
    };

    # dgop is not available in the current nixpkgs pin.
    enableSystemMonitoring = false;

    # The Niri config starts DMS, which keeps it out of the Plasma session.
    systemd.enable = false;
  };

  services.iio-niri.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    libnotify
    playerctl
    swayidle
    swaylock
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
      after = [ "graphical-session.target" ];
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

  system.activationScripts.niriConfig.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config/niri
    install -d -m 0755 -o mariano -g users /home/mariano/.config/niri/dms
    for dms_niri_include in outputs.kdl cursor.kdl colors.kdl wpblur.kdl alttab.kdl windowrules.kdl binds.kdl; do
      if [ ! -e "/home/mariano/.config/niri/dms/$dms_niri_include" ]; then
        install -m 0644 -o mariano -g users /dev/null "/home/mariano/.config/niri/dms/$dms_niri_include"
      fi
    done
    install -m 0644 -o mariano -g users ${../../dotfiles/niri/config.kdl} /home/mariano/.config/niri/config.kdl

    install -d -m 0755 -o mariano -g users /home/mariano/.config/DankMaterialShell
    install -m 0644 -o mariano -g users ${../../dotfiles/dms/theme.json} /home/mariano/.config/DankMaterialShell/theme.json

    dms_plugins=/home/mariano/.config/DankMaterialShell/plugin_settings.json
    dms_plugins_tmp="$(mktemp)"
    if [ -f "$dms_plugins" ]; then
      ${pkgs.jq}/bin/jq \
        '. + {
          codexBar: ((.codexBar // {}) + {
            enabled: true,
            codexbarPath: "${codexbar}/bin/codexbar",
            refreshInterval: "120000",
            sourceMode: "oauth"
          }),
          catWidget: ((.catWidget // {}) + {
            enabled: true
          }),
          codeIsland: ((.codeIsland // {}) + {
            enabled: true
          })
        }' \
        "$dms_plugins" > "$dms_plugins_tmp"
    else
      ${pkgs.jq}/bin/jq -n \
        '{
          codexBar: {
            enabled: true,
            codexbarPath: "${codexbar}/bin/codexbar",
            refreshInterval: "120000",
            sourceMode: "oauth"
          },
          catWidget: {
            enabled: true
          },
          codeIsland: {
            enabled: true
          }
        }' > "$dms_plugins_tmp"
    fi
    install -m 0644 -o mariano -g users "$dms_plugins_tmp" "$dms_plugins"
    rm -f "$dms_plugins_tmp"

    dms_settings=/home/mariano/.config/DankMaterialShell/settings.json
    dms_settings_tmp="$(mktemp)"
    if [ -f "$dms_settings" ]; then
      ${pkgs.jq}/bin/jq \
        --slurpfile barConfigs ${../../dotfiles/dms/bar-configs.json} \
        '. + {
          currentThemeCategory: "custom",
          currentThemeName: "custom",
          customThemeFile: "/home/mariano/.config/DankMaterialShell/theme.json"
        }
        | .barConfigs = $barConfigs[0]' \
        "$dms_settings" > "$dms_settings_tmp"
    else
      ${pkgs.jq}/bin/jq -n \
        --slurpfile barConfigs ${../../dotfiles/dms/bar-configs.json} \
        '{
          currentThemeCategory: "custom",
          currentThemeName: "custom",
          customThemeFile: "/home/mariano/.config/DankMaterialShell/theme.json",
          barConfigs: $barConfigs[0]
        }' > "$dms_settings_tmp"
    fi
    install -m 0644 -o mariano -g users "$dms_settings_tmp" "$dms_settings"
    rm -f "$dms_settings_tmp"

    install -d -m 0755 -o mariano -g users /home/mariano/.local/state/DankMaterialShell
    dms_session=/home/mariano/.local/state/DankMaterialShell/session.json
    dms_session_tmp="$(mktemp)"
    if [ -f "$dms_session" ]; then
      ${pkgs.jq}/bin/jq \
        '. + {
          weatherLocation: "Campana, Buenos Aires, Argentina",
          weatherCoordinates: "-34.16327,-58.95919"
        }' \
        "$dms_session" > "$dms_session_tmp"
    else
      ${pkgs.jq}/bin/jq -n \
        '{
          weatherLocation: "Campana, Buenos Aires, Argentina",
          weatherCoordinates: "-34.16327,-58.95919"
        }' > "$dms_session_tmp"
    fi
    install -m 0644 -o mariano -g users "$dms_session_tmp" "$dms_session"
    rm -f "$dms_session_tmp"
  '';
}
