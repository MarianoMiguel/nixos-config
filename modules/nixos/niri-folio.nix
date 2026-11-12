# ackerman's desktop: niri with Mariano's Folio shell, DMS only as Folio's
# fallback, and the tools around them. It is the desktop every workstation ran
# until 2026-11-01, restored from the archive/interstellar-niri branch for the
# M5 Max by Mariano's choice (2026-11-08). bonhart and balerion run GNOME
# (desktop.nix, gnome.nix) and never import this.
#
# Its dotfiles live in dotfiles-niri/, not dotfiles/: home.nix copies
# dotfiles/ whole into every system that imports it, so a file added there
# would change bonhart's and balerion's builds.
#
# hosts/ackerman/desktop.nix starts the session (niri on the GPU, from the
# tty1 login) and picks the niri package.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = "/home/mariano";
  mutableState = "${home}/.local/state/nixos-config/dotfiles";
  niriDotfiles = ../../dotfiles-niri/niri;
  dmsDotfiles = ../../dotfiles-niri/dms;
  niri = config.programs.niri.package;
  fingerprintEnabled = config.services.fprintd.enable;

  # azure-folio as the niri desktop had it: DMS takes the plate and fonts from
  # it again (patches/azure-folio-niri.patch). It wins over themeport.nix's
  # copy in the system profile, which Folio, DMS and FolioSync call.
  azureFolio = (pkgs.callPackage ../../packages/azure-folio.nix { }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      chmod u+w "$out/share/azure-folio/azure_folio.py"
      patch "$out/share/azure-folio/azure_folio.py" < ${../../patches/azure-folio-niri.patch}
    '';
  });

  # DMS's state and the niri includes it regenerates: writable, seeded once
  # into the same state folder as home.nix's, then left to DMS.
  mutableDotfiles = {
    "dms/plugin-settings.json" = "${dmsDotfiles}/plugin-settings.json";
    "dms/session.json" = "${dmsDotfiles}/session.json";
    "dms/settings.json" = "${dmsDotfiles}/settings.json";
    "dms/theme.json" = "${dmsDotfiles}/theme.json";
  }
  // lib.genAttrs (map (name: "niri/dms/${name}.kdl") [
    "alttab"
    "binds"
    "colors"
    "cursor"
    "layout"
    "outputs"
    "windowrules"
    "wpblur"
  ]) (path: "${niriDotfiles}/${lib.removePrefix "niri/" path}")
  // lib.genAttrs (map (name: "niri/toggles/${name}.kdl") [
    "gaps"
    "border"
    "radius"
  ]) (path: "${niriDotfiles}/${lib.removePrefix "niri/" path}");
  mutableDotfileSeed = pkgs.runCommandLocal "mariano-niri-folio-seed" { } (
    lib.concatStrings (
      lib.mapAttrsToList (path: source: ''
        install -Dm0644 ${source} "$out/${path}"
      '') mutableDotfiles
    )
  );
in
{
  imports = [
    ./capture.nix
    ./folio-shell.nix
    ./niri.nix
    ./niri-actions.nix
    ./niri-pip.nix
    ./workspace-modes.nix
  ];

  # Folio is the shell; DMS runs only when Folio keeps failing or after
  # `mariano-shell use dms`.
  mariano.folio.default = "folio";

  # X11 windows go without xwayland-satellite's own white title bar.
  nixpkgs.overlays = [ (import ../../overlays/xwayland-satellite-no-fallback-titlebar.nix) ];

  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.niri = {
      default = [
        "gnome"
        "gtk"
      ];
      "org.freedesktop.impl.portal.Access" = "gtk";
      "org.freedesktop.impl.portal.AppChooser" = "gtk";
      "org.freedesktop.impl.portal.Notification" = "gtk";
      "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
    };
  };

  # GTK apps take the color scheme, fonts and window lights from dconf
  # (through the settings portal); home.nix and themeport write them there.
  programs.dconf.enable = true;

  # Qt applications use the KDE platform theme and Breeze so they read
  # Themeport's ~/.config/kdeglobals, and draw Interstellar's title bar.
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };
  environment.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
    QT_WAYLAND_DECORATION = "interstellar";
  };

  environment.systemPackages = [
    (pkgs.callPackage ../../packages/qt-interstellar-decorations { })
    (lib.hiPrio azureFolio)
  ];

  home-manager.users.mariano =
    { config, lib, marianoCodexbar, ... }:
    let
      mutableDotfile = path: config.lib.file.mkOutOfStoreSymlink "${mutableState}/${path}";
    in
    {
      dconf.settings = {
        "org/gnome/desktop/peripherals/mouse"."natural-scroll" = false;
        "org/gnome/desktop/peripherals/touchpad"."natural-scroll" = false;
        # Interstellar's window lights at the start of the title bar: close,
        # then maximize (niri has no minimize). themeport draws them.
        "org/gnome/desktop/wm/preferences"."button-layout" = "close,maximize:";
      };

      xdg.configFile =
        {
          "niri/config.kdl".source = "${niriDotfiles}/config.kdl";
          "niri/manifesto.kdl".source = "${niriDotfiles}/manifesto.kdl";
          "niri/modes.kdl".source = "${niriDotfiles}/modes.kdl";
          "niri/resize.kdl".source = "${niriDotfiles}/resize.kdl";
          "niri/style-toggles.kdl".source = "${niriDotfiles}/style-toggles.kdl";
          "niri/themeport.kdl".source = "${niriDotfiles}/themeport.kdl";

          # Standalone Quickshell instance (qs -c desktop-click), spawned by
          # the niri config: exposed wallpaper jumps to the nearest empty
          # workspace on that display.
          "quickshell/desktop-click/shell.qml".source =
            ../../dotfiles-niri/quickshell/desktop-click/shell.qml;

          "DankMaterialShell/theme.json".source = mutableDotfile "dms/theme.json";
          "DankMaterialShell/themes/themeport/theme.json".source = mutableDotfile "themeport/dms/theme.json";
          "DankMaterialShell/settings.json".source = mutableDotfile "dms/settings.json";
          "DankMaterialShell/plugin_settings.json".source = mutableDotfile "dms/plugin-settings.json";
        }
        // lib.genAttrs (builtins.filter (lib.hasPrefix "niri/") (builtins.attrNames mutableDotfiles)) (path: {
          source = mutableDotfile path;
        });
      home.file.".local/state/DankMaterialShell/session.json".source = mutableDotfile "dms/session.json";

      # Seed DMS's state before home.nix seeds its own list, which has the
      # login screen's (GNOME machines') dms/settings.json and session.json:
      # the first seed of a path wins, so DMS starts from its full settings.
      home.activation.seedNiriFolioDotfiles = lib.hm.dag.entryBefore [ "seedMutableDotfiles" ] ''
        ${lib.concatStrings (
          lib.mapAttrsToList (path: _: ''
            if [ ! -e ${lib.escapeShellArg "${mutableState}/${path}"} ]; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm0600 \
                ${lib.escapeShellArg "${mutableDotfileSeed}/${path}"} \
                ${lib.escapeShellArg "${mutableState}/${path}"}
            fi
          '') mutableDotfiles
        )}
      '';

      # Qt caches plugins under stable /etc paths, while Nix store files all
      # have the same epoch timestamp. Invalidate compiled QML when the local
      # plugin sources change so a restart cannot load an earlier catalog.
      home.activation.refreshDmsPluginCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        marker="${home}/.local/state/nixos-config/dms-plugin-cache-revision"
        revision="${../../dotfiles-niri/dms-plugins}"
        previous="$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || true)"
        if [ "$previous" != "$revision" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf "${home}/.cache/quickshell/qmlcache"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${home}/.local/state/nixos-config"
          if [ -z "$DRY_RUN_CMD" ]; then
            printf '%s\n' "$revision" > "$marker"
          fi
        fi
      '';

      # These DMS settings are policy rather than preferences: one visual
      # owner (Interstellar, through themeport's custom theme), no mutable
      # user Matugen templates or third-party launcher entries executing as
      # part of a theme switch. Every other DMS preference is kept.
      home.activation.enforceDmsConsistency = lib.hm.dag.entryAfter [ "seedMutableDotfiles" ] ''
        # DMS writes these files live, so a crash or a full disk mid-write
        # can leave a truncated file. Rather than failing every later
        # activation, keep the damaged copy for inspection and re-seed from
        # the store so the policy below still applies.
        ensure_json_object() {
          file=$1
          seed=$2
          if ${pkgs.jq}/bin/jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
            return 0
          fi
          broken="$file.broken-$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
          echo "DMS state $file is not a JSON object; kept at $broken and re-seeded from the store copy." >&2
          if [ -e "$file" ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv -f "$file" "$broken"
          fi
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$seed" "$file"
        }

        settings=${lib.escapeShellArg "${mutableState}/dms/settings.json"}
        ensure_json_object "$settings" ${lib.escapeShellArg "${mutableDotfileSeed}/dms/settings.json"}
        temporary="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.jq}/bin/jq \
          --argjson fingerprint ${builtins.toJSON fingerprintEnabled} \
          --arg theme ${lib.escapeShellArg "${home}/.config/DankMaterialShell/themes/themeport/theme.json"} '
          .currentThemeName = "custom"
          | .currentThemeCategory = "custom"
          | .customThemeFile = $theme
          | .fontFamily = "Inter"
          | .monoFontFamily = "IBM Plex Mono"
          | .lockScreenFontFamily = "Jacquard 24"
          | .greeterFontFamily = "Inter"
          | .fontWeight = 400
          | .fontScale = 1
          | .widgetRadius = 5
          | .runUserMatugenTemplates = false
          | .showThirdPartyPlugins = false
          | .searchAppActions = true
          | .launcherStyle = "full"
          | .dankLauncherV2Size = "medium"
          | .gtkThemingEnabled = true
          | .qtThemingEnabled = false
          | .matugenTemplateGtk = true
          | .greeterEnableFprint = $fingerprint
          | .enableFprint = $fingerprint
          | .lockBeforeSuspend = true
          | .powerMenuActions = ["lock", "logout", "reboot", "poweroff"]
          | .powerMenuDefaultAction = "lock"
          | .powerMenuGridLayout = false
          | .powerActionConfirm = true
          # Idle locks and blanks but never sleeps: the M5 Max has no
          # hibernation, and the bring-up decides its suspend policy
          # (hosts/ackerman), not the fallback shell.
          | .acSuspendTimeout = 0
          | .batterySuspendTimeout = 0
          | .animationSpeed = 4
          | .customAnimationDuration = 0
          | .syncComponentAnimationSpeeds = true
          # No motion on ackerman (Mariano, 2026-11-08): reduce motion, and no custom durations
          | .reduceMotion = true
          | .springBounce = 0
          | .popoutAnimationSpeed = 4
          | .popoutCustomAnimationDuration = 0
          | .modalAnimationSpeed = 4
          | .modalCustomAnimationDuration = 0
          | .notificationAnimationSpeed = 4
          | .notificationCustomAnimationDuration = 0
          | .controlCenterShowIdleInhibitorIcon = false
          | .controlCenterShowDoNotDisturbIcon = false
          | .fadeToLockEnabled = false
          | .fadeToLockGracePeriod = 0
          | .lockScreenShowPowerActions = false
          | .lockScreenShowSystemIcons = false
          | .lockScreenShowTime = true
          | .lockScreenShowDate = true
          | .lockScreenShowProfileImage = false
          | .lockScreenShowPasswordField = true
          | .lockScreenShowMediaPlayer = false
          | .lockScreenNotificationMode = 0
          | .lockScreenVideoEnabled = false
          | .barConfigs = [.barConfigs[] | . + {
              leftWidgets: ["launcherButton", "workspaceSwitcher", "focusedWindow"],
              centerWidgets: ["clock"],
              rightWidgets: ["systemTray", "battery", {id:"folioSidebar",enabled:true}],
              spacing: 8, innerPadding: 2, bottomGap: 0,
              transparency: 1, widgetTransparency: 0,
              squareCorners: false, noBackground: false,
              borderEnabled: true, borderColor: "outlineVariant", borderOpacity: 1,
              borderThickness: 1, widgetPadding: 8,
              shadowIntensity: 0, shadowOpacity: 0
            }]
        ' "$settings" > "$temporary"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$settings"
        ${pkgs.coreutils}/bin/rm -f "$temporary"

        # System-wide plugin installation and mutable enablement are separate
        # in DMS. Keep the reviewed plugins active on upgrades and fresh
        # installs while preserving every other plugin's settings.
        plugin_settings=${lib.escapeShellArg "${mutableState}/dms/plugin-settings.json"}
        ensure_json_object "$plugin_settings" ${lib.escapeShellArg "${mutableDotfileSeed}/dms/plugin-settings.json"}
        temporary="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.jq}/bin/jq \
          --arg codexbar ${lib.escapeShellArg "${marianoCodexbar}/bin/codexbar"} '
          .folioSidebar.enabled = true
          | .focus.enabled = true
          | .codexBar.enabled = true
          | .codexBar.codexbarPath = $codexbar
          | .codexBar.refreshInterval = "60000"
          | .codexBar.sourceMode = "oauth"
          | .systemMenu.enabled = true
          | .themePicker.enabled = true
          | .wallpaperPicker.enabled = true
          | .workspaceModes.enabled = true
          | .worldClock.enabled = true
        ' "$plugin_settings" > "$temporary"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$plugin_settings"
        ${pkgs.coreutils}/bin/rm -f "$temporary"

        # Keep DMS's launcher and system-menu bindings as checked in, even if
        # DMS's keybind editor rewrote this mutable file.
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 \
          ${niriDotfiles}/dms/binds.kdl \
          ${lib.escapeShellArg "${mutableState}/niri/dms/binds.kdl"}
      '';

      # A rebuild swaps the niri/config.kdl symlink to a new store path, but
      # niri's inotify watch is on the old target and never fires, so it keeps
      # the old config in memory until the next relogin. Poke it to re-read
      # the freshly linked config. Best-effort: niri may not be running (no
      # socket to find), and a reload must never fail activation. niri msg
      # needs NIRI_SOCKET set explicitly, so resolve it from the runtime dir.
      home.activation.reloadNiri = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        runtime="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
        # At boot the unit runs before login, with no $runtime yet: find exits 1, and under
        # activation's pipefail that failed the whole activation (ackerman, 2026-11-08 21:57).
        socket="$(${pkgs.findutils}/bin/find "$runtime" -maxdepth 1 -name 'niri.*.sock' 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)"
        if [ -n "$socket" ]; then
          $DRY_RUN_CMD env NIRI_SOCKET="$socket" ${niri}/bin/niri msg action load-config-file || true
        fi
      '';
    };
}
