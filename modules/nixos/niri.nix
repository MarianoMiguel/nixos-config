# niri, DMS (Folio's fallback, folio-shell.nix) and the tools around them: the
# DMS plugins, LibrePods, CodexBar, CodeIsland. Part of the niri + Folio
# desktop (niri-folio.nix), which only ackerman runs.
{
  config,
  lib,
  pkgs,
  cat-dms,
  codeIsland-dms,
  dms,
  dms-codexbar,
  librepods-rust,
  quickshell,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  niri = config.programs.niri.package;
  librepods = librepods-rust.packages.${system}.default;
  # The Rust package currently installs only its binary even though upstream
  # ships a desktop entry and icon. Provide the missing launcher so LibrePods
  # appears in the shells' launchers.
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
  niriStyleToggle = pkgs.writeShellApplication {
    name = "niri-style-toggle";
    runtimeInputs = with pkgs; [ coreutils gnugrep ];
    text = ''
      set -eu

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nixos-config/dotfiles/niri/toggles"
      mkdir -p "$state_dir"

      case "''${1:-}" in
        gaps)
          target="$state_dir/gaps.kdl"
          if grep -q '^[[:space:]]*gaps 0[[:space:]]*$' "$target" 2>/dev/null; then
            printf '%s\n' '// Window gaps use the current DMS value.' > "$target"
          else
            printf '%s\n' \
              '// Window gaps temporarily disabled.' \
              'layout {' \
              '    gaps 0' \
              '}' > "$target"
          fi
          ;;
        border)
          target="$state_dir/border.kdl"
          if grep -q '^[[:space:]]*off[[:space:]]*$' "$target" 2>/dev/null; then
            printf '%s\n' '// Window borders use the current DMS value.' > "$target"
          else
            printf '%s\n' \
              '// Window borders temporarily disabled.' \
              'layout {' \
              '    border {' \
              '        off' \
              '    }' \
              '}' > "$target"
          fi
          ;;
        radius)
          target="$state_dir/radius.kdl"
          if grep -q '^[[:space:]]*geometry-corner-radius 0[[:space:]]*$' "$target" 2>/dev/null; then
            printf '%s\n' '// Window corners use the current DMS radius.' > "$target"
          else
            printf '%s\n' \
              '// Window corner radius temporarily disabled.' \
              'window-rule {' \
              '    geometry-corner-radius 0' \
              '}' > "$target"
          fi
          ;;
        *)
          printf 'usage: niri-style-toggle gaps|border|radius\n' >&2
          exit 2
          ;;
      esac
    '';
  };
  # Backs the wallpaper click surface (dotfiles-niri/quickshell/desktop-click).
  niriFocusEmpty = pkgs.writeShellApplication {
    name = "niri-focus-empty";
    runtimeInputs = with pkgs; [
      jq
      niri
    ];
    text = builtins.readFile ../../scripts/niri-focus-empty.sh;
  };
  networkSpeedtest = pkgs.writeShellApplication {
    name = "mariano-network-speedtest";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      librespeed-cli
      util-linux
    ];
    text = builtins.readFile ../../scripts/network-speedtest.sh;
  };
  tailscaleConnect = pkgs.writeShellApplication {
    name = "mariano-tailscale-connect";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      libnotify
      tailscale
      xdg-utils
    ];
    text = ''
      set -u

      open_auth_url() {
        payload=$1
        auth_url=$(printf '%s' "$payload" | jq -er '
          select(type == "object")
          | .AuthURL
          | select(type == "string")
          | select(test("^https://login\\.tailscale\\.com/"))
        ' 2>/dev/null) || return 1

        if xdg-open "$auth_url"; then
          notify-send "Tailscale" "Complete sign-in in your browser."
          return 0
        fi

        notify-send --urgency=critical "Tailscale" "Could not open the sign-in page."
        return 1
      }

      # A logged-out daemon normally already exposes its current authentication
      # URL through `tailscale status`. Using it avoids spawning a command that
      # waits for login before returning.
      status_json=$(tailscale status --json 2>/dev/null || true)
      if open_auth_url "$status_json"; then
        exit 0
      fi

      output=$(mktemp)
      errors=$(mktemp)
      trap 'rm -f "$output" "$errors"' EXIT

      if tailscale up --json --timeout=2s >"$output" 2>"$errors"; then
        result=0
      else
        result=$?
      fi
      if open_auth_url "$(cat "$output")"; then
        exit 0
      fi

      if [ "$result" -eq 0 ]; then
        notify-send "Tailscale" "Connected."
        exit 0
      fi

      backend_state=$(printf '%s' "$status_json" | jq -r '.BackendState // "unknown"' 2>/dev/null || printf unknown)
      notify-send --urgency=critical "Tailscale" \
        "Could not connect (state: $backend_state). Run tailscale up in a terminal for details."
      exit "$result"
    '';
  };
  codexbarArch = pkgs.stdenv.hostPlatform.parsed.cpu.name;
  codexbarHashes = {
    x86_64 = "sha256-Mx2Zs5X2ZniPmqCB5Dk66yYP7DlE5sh/FRzp1mh7J04=";
    aarch64 = "sha256-9v+YcYP/RtIOUxdBSGcLHvMTY/dJnh4xlbRLprbHJlc=";
  };
  codexbarUnwrapped = pkgs.stdenvNoCC.mkDerivation {
    pname = "codexbar-unwrapped";
    version = "0.55.0";

    src = pkgs.fetchzip {
      url = "https://github.com/steipete/CodexBar/releases/download/v0.55.0/CodexBarCLI-v0.55.0-linux-${codexbarArch}.tar.gz";
      sha256 = codexbarHashes.${codexbarArch};
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
      cp -R CodexBar_CodexBarCore.bundle "$out/bin/"
      install -Dm0644 VERSION "$out/bin/VERSION"
      runHook postInstall
    '';
  };

  # CodexBar reports provider CLI versions by looking them up in PATH. Its
  # Linux Swift build can trap in Foundation.Process when that lookup runs
  # below Quickshell or systemd. Point the Codex probe at a known executable so
  # it never needs the fragile nested `which` process; retain ~/.local/bin for
  # provider CLIs installed outside the system profile.
  codexbar = pkgs.symlinkJoin {
    name = "codexbar-${codexbarUnwrapped.version}";
    paths = [ codexbarUnwrapped ];
    postBuild = ''
      for binary in codexbar CodexBarCLI; do
        rm "$out/bin/$binary"
        ${pkgs.coreutils}/bin/tee "$out/bin/$binary" >/dev/null <<EOF
#!${pkgs.runtimeShell}
export PATH="\$HOME/.local/bin:\$PATH"
export CODEX_CLI_PATH="${pkgs.codex}/bin/codex"
exec "${codexbarUnwrapped}/bin/$binary" "\$@"
EOF
        chmod 0755 "$out/bin/$binary"
      done
    '';
  };

  # CodexBar returns useful JSON for authenticated providers even when another
  # requested provider fails. Keep those partial results instead of turning the
  # entire widget into an error, and support providers without a primary window.
  codexbarDmsPlugin = pkgs.applyPatches {
    name = "dms-codexbar-focused-usage";
    src = dms-codexbar;
    patches = [ ../../patches/dms-codexbar-partial-results.patch ];
  };

  folio = pkgs.callPackage ../../packages/azure-folio.nix { };
  # Folio's QML inside DMS: the backdrop (shared with the login screen of the
  # GNOME machines, so it is labelled for niri here) and FolioSync, which
  # keeps DMS's light/dark toggle and wallpaper in step with azure-folio.
  folioQml = pkgs.runCommand "azure-folio-qml" { } ''
    mkdir -p "$out"
    install -m 0644 ${../../dotfiles/azure-folio/FolioBackdrop.qml} "$out/FolioBackdrop.qml"
    install -m 0644 ${../../dotfiles-niri/azure-folio/FolioSync.qml} "$out/FolioSync.qml"
    substituteInPlace "$out/FolioBackdrop.qml" \
      --replace-fail '@folioData@' '${folio}/share/azure-folio' \
      --replace-fail '"@hostname@ · GNOME"' '"${config.networking.hostName} · NIRI"'
  '';

  # DMS's custom motion base already keeps expressive transitions at or below
  # 80 ms. Two inline notification transitions bypass that base upstream, so
  # bind them back to the configured duration in the installed shell.
  dmsShell = dms.packages.${system}.dms-shell.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      chmod u+w "$out/share/quickshell/dms" \
        "$out/share/quickshell/dms/Modules/Lock" \
        "$out/share/quickshell/dms/Modules/Lock/LockScreenContent.qml"
      patch -d "$out/share/quickshell/dms" -p2 < ${../../patches/dms-azure-folio-lock.patch}
      chmod u+w "$out/share/quickshell/dms/Common" \
        "$out/share/quickshell/dms/Services" \
        "$out/share/quickshell/dms/Modules/Dock"
      patch -d "$out/share/quickshell/dms" -p1 < ${../../patches/dms-cmux-and-shared-wallpaper.patch}
      mkdir -p "$out/share/quickshell/dms/Folio"
      cp ${folioQml}/*.qml "$out/share/quickshell/dms/Folio/"
      substituteInPlace "$out/share/quickshell/dms/shell.qml" \
        --replace-fail 'import qs.Services' 'import qs.Services
import qs.Folio' \
        --replace-fail '    id: entrypoint' '    id: entrypoint
    FolioSync {}'
      substituteInPlace "$out/share/quickshell/dms/Common/Theme.qml" \
        --replace-fail \
          'readonly property int notificationInlineExpandDuration: notificationAnimationBaseDuration === 0 ? 0 : 185' \
          'readonly property int notificationInlineExpandDuration: notificationAnimationBaseDuration' \
        --replace-fail \
          'readonly property int notificationInlineCollapseDuration: notificationAnimationBaseDuration === 0 ? 0 : 150' \
          'readonly property int notificationInlineCollapseDuration: notificationAnimationBaseDuration === 0 ? 0 : Math.round(notificationAnimationBaseDuration * 0.85)'

      # Expressive size multipliers otherwise exceed the requested 100 ms cap.
      substituteInPlace "$out/share/quickshell/dms/Common/Theme.qml" \
        --replace-fail '"large": baseDuration * 1.2' '"large": Math.min(100, baseDuration * 1.2)' \
        --replace-fail '"extraLarge": baseDuration * 2.0' '"extraLarge": Math.min(100, baseDuration * 2.0)'

      # The shipped widgets are reviewed Nix inputs. Do not execute mutable
      # plugins from ~/.config/DankMaterialShell/plugins, even if a catalog or
      # a local process writes files there.
      substituteInPlace "$out/share/quickshell/dms/Services/PluginService.qml" \
        --replace-fail \
          'userWatcher.folder = Paths.toFileUrl(root.pluginDirectory);' \
          'userWatcher.folder = "";' \
        --replace-fail \
          'const userList = snapshotModel(userWatcher, "user");' \
          'const userList = [];' \
        --replace-fail \
          'const userUrl = Paths.toFileUrl(root.pluginDirectory);' \
          'const userUrl = "";'

    ''
    # DMS's backend toggles WantRunning, which reconnects an enrolled node but
    # cannot begin interactive authentication for a logged-out one. Delegate
    # login states to a small helper that opens the LocalAPI-provided URL;
    # retain DMS's native backend for ordinary reconnects. Only where
    # Tailscale runs (not on ackerman today).
    + lib.optionalString config.services.tailscale.enable ''
      substituteInPlace "$out/share/quickshell/dms/Services/TailscaleService.qml" \
        --replace-fail \
          '        sendAction("tailscale.connect", null, callback);' \
          '        if (backendState === "NeedsLogin" || backendState === "NoState" || backendState === "NeedsMachineAuth") { Quickshell.execDetached(["${tailscaleConnect}/bin/mariano-tailscale-connect"]); return; } sendAction("tailscale.connect", null, callback);'
    ''
    + ''

      # Tailscale advertises a DBusMenu-only tray item. Quickshell's generic
      # menu renderer intermittently fails to instantiate that menu, while DMS
      # already has a richer native Tailscale detail with connect, peer, exit
      # node, and LAN-access controls. Route a left click on every tray layout
      # to that native detail instead.
      chmod u+w \
        "$out/share/quickshell/dms/Modules/DankBar" \
        "$out/share/quickshell/dms/Modules/DankBar/Widgets" \
        "$out/share/quickshell/dms/Modules/DankBar/DankBarWindow.qml" \
        "$out/share/quickshell/dms/Modules/DankBar/Widgets/SystemTrayBar.qml"
      patch -d "$out/share/quickshell/dms" -p1 \
        < ${../../patches/dms-tailscale-native-tray.patch}
    '';
  });

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
  imports = [
    dms.nixosModules.dank-material-shell
    ./app-sets.nix
  ];

  # Keep the mutable DMS plugin settings pinned to the same reviewed CodexBar
  # package as the system profile instead of relying on whichever executable
  # happens to appear first in the shell service's PATH.
  home-manager.extraSpecialArgs.marianoCodexbar = codexbar;

  programs.niri.enable = true;

  # Keep the compositor and shell responsive when builds or AI agents saturate
  # the CPU. CPUWeight only changes scheduling under contention.
  systemd.user.services.niri.serviceConfig.CPUWeight = 250;

  programs.dank-material-shell = {
    enable = true;
    package = dmsShell;
    quickshell.package = quickshell.packages.${system}.default;
    plugins = {
      # Composite plugin: one shared sidebar daemon, a button on each bar.
      # All content lives in this repo and reuses DMS services/plugin panels.
      folioSidebar = {
        src = ../../dotfiles-niri/dms-plugins/folio-sidebar;
        settings.enabled = true;
      };
      codexBar = {
        src = codexbarDmsPlugin;
        settings = {
          enabled = true;
          codexbarPath = "${codexbar}/bin/codexbar";
          refreshInterval = "60000";
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
      focus = {
        src = ../../dotfiles-niri/dms-plugins/focus;
        settings.enabled = true;
      };
      networkSpeed = {
        src = ../../dotfiles-niri/dms-plugins/network-speed;
        settings.enabled = true;
      };
      # Globe icon left of the clock: Campana, New York, Los Angeles and
      # Sydney times in a popout, converted by `date` because the QML JS
      # engine has no timezone database.
      worldClock = {
        src = ../../dotfiles-niri/dms-plugins/world-clock;
        settings.enabled = true;
      };
      # Per-monitor switcher for the current workspace's window mode. The
      # niri-modes daemon in modules/nixos/workspace-modes.nix owns the state;
      # this widget is a view and a remote control.
      workspaceModes = {
        src = ../../dotfiles-niri/dms-plugins/workspace-modes;
        settings.enabled = true;
      };
      # DMS's app launcher carries the theme-aware system surface: a
      # searchable control palette (niri-actions.nix) plus image-first theme
      # and wallpaper browsers.
      systemMenu = {
        src = ../../dotfiles-niri/dms-plugins/system-menu;
        settings.enabled = true;
      };
      themePicker = {
        src = ../../dotfiles-niri/dms-plugins/theme-picker;
        settings.enabled = true;
      };
      wallpaperPicker = {
        src = ../../dotfiles-niri/dms-plugins/wallpaper-picker;
        settings.enabled = true;
      };
    };

    # dgop is not available in the current nixpkgs pin.
    enableSystemMonitoring = false;

    # mariano-shell (folio-shell.nix) starts DMS, and only when it is the
    # chosen shell or Folio's fallback, so dms.service is not bound to the
    # session. Its unit comes with the package; the drop-in below sets its PATH.
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
    wl-mirror
    wtype
    xwayland-satellite
    niriStyleToggle
    niriFocusEmpty
    networkSpeedtest
    codexbar
    codeIslandLinux
  ]
  # LibrePods is one of the big apps (app-sets.nix)
  ++ lib.optionals config.mariano.bigApps.enable [
    librepods
    librepodsDesktopItem
  ]
  ++ lib.optional config.services.tailscale.enable tailscaleConnect;

  systemd.user.tmpfiles.rules = [
    "d %h/.config/librepods 0700 - -"
    "d %h/.local/share/librepods 0700 - -"
    "f %h/.local/share/librepods/devices.json 0600 - - - {}"
  ];

  systemd.user.services = {
    dms = {
      overrideStrategy = "asDropin";
      # A user service does NOT inherit the manager's show-environment PATH:
      # with no path it gets systemd's minimal built-in PATH and cannot find
      # `qs`, so DMS never starts. So set an explicit, COMPLETE path. It must
      # stay complete because DMS's launcher hands this same PATH to the apps
      # it starts: /run/wrappers first so a launched terminal resolves the
      # setuid sudo, then ~/.local/bin for native CLIs, the per-user profile,
      # and the system profile for qs and the rest.
      path = [
        "/run/wrappers"
        "%h/.local"
        "/etc/profiles/per-user/mariano"
        "/run/current-system/sw"
      ];
      serviceConfig.CPUWeight = 150;
    };

    librepods = lib.mkIf config.mariano.bigApps.enable {
      description = "LibrePods AirPods integration";
      partOf = [ "graphical-session.target" ];
      # Ordered after whichever shell runs (its tray is what ExecStartPre waits
      # for); it must not pull DMS in, or switching to Folio would stop.
      after = [ "dms.service" "folio-shell.service" ];
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
