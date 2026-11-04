{
  config,
  dank-greeter,
  lib,
  pkgs,
  ...
}:

# The login screen: greetd running DMS's greeter in a bare niri, in
# Interstellar's look (patches/dms-azure-folio-greeter.patch draws the Folio
# backdrop from the selection azure-folio publishes in
# /var/lib/azure-folio/appearance.json). It is the only thing left of DMS and
# niri, and it stays until a GDM login screen is styled to match the
# disk-unlock screen; then this module, the dank-greeter input, the patch and
# dotfiles/azure-folio go together. niri here is only the greeter's
# compositor: programs.niri is off, so it is not a session.
let
  system = pkgs.stdenv.hostPlatform.system;
  home = "/home/mariano";
  mutableState = "${home}/.local/state/nixos-config/dotfiles";
  fingerprintEnabled = config.services.fprintd.enable;
  folio = pkgs.callPackage ../../packages/azure-folio.nix { };

  # DMS's greeter launches the desktop entry's Exec command, but it does not
  # export DesktopNames as XDG_CURRENT_DESKTOP. GNOME Control Center rejects
  # the resulting session even though GNOME Shell is running, so give the
  # GNOME session an explicit environment-importing launcher.
  gnomeSessionLauncher = pkgs.writeShellScript "gnome-session-with-desktop-env" ''
    export XDG_CURRENT_DESKTOP=GNOME
    export XDG_SESSION_DESKTOP=gnome
    export DESKTOP_SESSION=gnome
    export GDMSESSION=gnome

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION GDMSESSION
    ${pkgs.dbus}/bin/dbus-update-activation-environment \
      XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION GDMSESSION

    ${pkgs.gnome-session}/bin/gnome-session "$@"
    sessionStatus=$?

    ${pkgs.systemd}/bin/systemctl --user unset-environment \
      XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION GDMSESSION
    exit "$sessionStatus"
  '';

  gnomeSessionsWithDesktopEnv = pkgs.runCommand "gnome-session-with-desktop-env" {
    passthru.providedSessions = [ "gnome" ];
  } ''
    mkdir -p "$out/share/wayland-sessions"
    substitute \
      ${pkgs.gnome-session.sessions}/share/wayland-sessions/gnome.desktop \
      "$out/share/wayland-sessions/gnome.desktop" \
      --replace-fail \
        'Exec=${pkgs.gnome-session}/bin/gnome-session' \
        'Exec=${gnomeSessionLauncher}'
  '';

  # Interstellar's backdrop for the greeter (dotfiles/azure-folio).
  folioQml = pkgs.runCommand "azure-folio-qml" { } ''
    mkdir -p "$out"
    cp ${../../dotfiles/azure-folio}/*.qml "$out/"
    substituteInPlace "$out/FolioBackdrop.qml" \
      --replace-fail '@folioData@' '${folio}/share/azure-folio' \
      --replace-fail '@hostname@' '${config.networking.hostName}'
  '';

  # The greeter UI ships from its own upstream flake. Fall back to the
  # session named in DMS_GREET_DEFAULT_SESSION when session remembering is
  # disabled, so GNOME is what it offers.
  dmsGreeter = dank-greeter.packages.${system}.default.overrideAttrs (old: {
    postPatch = ''
      patch -p1 < ${../../patches/dms-azure-folio-greeter.patch}
      mkdir -p quickshell/Folio
      cp ${folioQml}/*.qml quickshell/Folio/
      substituteInPlace quickshell/Modules/Greetd/GreeterContent.qml \
        --replace-fail \
          'const savedDesktopId = GreetdSettings.rememberLastSession ? (GreetdMemory.lastSessionDesktopId || desktopIdFromPath(GreetdMemory.lastSessionId)) : "";' \
          'const savedDesktopId = (GreetdSettings.rememberLastSession ? (GreetdMemory.lastSessionDesktopId || desktopIdFromPath(GreetdMemory.lastSessionId)) : "") || Quickshell.env("DMS_GREET_DEFAULT_SESSION") || "";' \
        --replace-fail \
          'if ((savedSession || savedDesktopId) && GreetdSettings.rememberLastSession) {' \
          'if (savedSession || savedDesktopId) {'
    '' + (old.postPatch or "");
  });
in
{
  services.displayManager.defaultSession = "gnome";
  # The one session on offer: GNOME through the launcher above.
  services.displayManager.sessionPackages = lib.mkForce [ gnomeSessionsWithDesktopEnv ];

  users.groups.greeter = { };
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    home = "/var/lib/dms-greeter";
  };

  services.greetd.settings.default_session.user = "greeter";
  security.pam.services.greetd.allowNullPassword = lib.mkForce false;
  systemd.services.greetd.environment = {
    # DMS does not consume services.displayManager.defaultSession. Its greeter
    # package uses this explicit fallback when session remembering is disabled.
    DMS_GREET_DEFAULT_SESSION = "gnome";
    DMS_GREET_REMEMBER_LAST_SESSION = "0";
    DMS_SAVE_SESSION = "false";
  };

  # Updating the login artwork must not terminate the active desktop session.
  # The rebuilt greeter is picked up when greetd next starts.
  systemd.services.greetd.restartIfChanged = false;

  programs.dms-greeter = {
    enable = true;
    package = dmsGreeter;
    compositor = {
      name = "niri";
      package = pkgs.niri;
    };
    # greetd's preStart copies three files from here into the greeter's cache:
    # ~/.config/DankMaterialShell/settings.json (clock, fonts, fingerprint,
    # power menu, and the custom theme it points to), ~/.local/state/
    # DankMaterialShell/session.json, and ~/.cache/DankMaterialShell/
    # dms-colors.json when present. The first two are kept below.
    configHome = home;
    logs = {
      save = true;
      path = "/var/lib/dms-greeter/dms-greeter.log";
    };
  };

  # The greeter's state in the home directory, now that the DMS shell that
  # used to own it is gone: writable files seeded once by home.nix
  # (dotfiles/dms/), and themeport's dms/theme.json, the palette the
  # settings name as the custom theme.
  home-manager.users.mariano =
    { config, lib, ... }:
    let
      mutableDotfile = path: config.lib.file.mkOutOfStoreSymlink "${mutableState}/${path}";
    in
    {
      xdg.configFile = {
        "DankMaterialShell/settings.json".source = mutableDotfile "dms/settings.json";
        "DankMaterialShell/themes/themeport/theme.json".source = mutableDotfile "themeport/dms/theme.json";
      };
      home.file.".local/state/DankMaterialShell/session.json".source = mutableDotfile "dms/session.json";

      # Keep the settings the greeter reads as they look today, on upgrades
      # and fresh installs alike, and preserve every other key. A crash or a
      # full disk mid-write could have left a truncated file: keep the damaged
      # copy for inspection and re-seed it so the policy still applies.
      home.activation.loginScreenSettings = lib.hm.dag.entryAfter [ "seedMutableDotfiles" ] ''
        settings=${lib.escapeShellArg "${mutableState}/dms/settings.json"}
        if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
          broken="$settings.broken-$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
          echo "Login screen settings $settings are not a JSON object; kept at $broken and re-seeded." >&2
          if [ -e "$settings" ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv -f "$settings" "$broken"
          fi
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 ${../../dotfiles/dms/settings.json} "$settings"
        fi
        temporary="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.jq}/bin/jq \
          --argjson fingerprint ${builtins.toJSON fingerprintEnabled} \
          --arg theme ${lib.escapeShellArg "${home}/.config/DankMaterialShell/themes/themeport/theme.json"} '
          .currentThemeName = "custom"
          | .customThemeFile = $theme
          | .clockFormat = "24h"
          | .fontFamily = "Inter"
          | .monoFontFamily = "IBM Plex Mono"
          | .fontWeight = 400
          | .fontScale = 1
          | .greeterEnableFprint = $fingerprint
          | .lockScreenShowPowerActions = false
          | .lockScreenShowProfileImage = false
          | .powerMenuActions = ["lock", "logout", "reboot", "poweroff"]
          | .powerMenuDefaultAction = "lock"
          | .powerMenuGridLayout = false
          | .powerActionConfirm = true
        ' "$settings" > "$temporary"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$settings"
        ${pkgs.coreutils}/bin/rm -f "$temporary"
      '';
    };
}
