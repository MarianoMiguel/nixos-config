{ lib, pkgs, ... }:

let
  # DMS greeter launches the desktop entry's Exec command, but it does not
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
in
{
  services.xserver.enable = true;

  services.displayManager.sddm.enable = false;
  services.displayManager.defaultSession = "niri";
  services.desktopManager.gnome.enable = true;
  # GNOME is the stock fallback; Niri with DMS remains the default. Avoid a
  # second desktop stack owning Bluetooth, display and package-management UI.
  services.displayManager.sessionPackages = lib.mkForce [
    pkgs.niri
    gnomeSessionsWithDesktopEnv
  ];

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
    DMS_GREET_DEFAULT_SESSION = "niri";
    DMS_GREET_REMEMBER_LAST_SESSION = "0";
    DMS_SAVE_SESSION = "false";
  };

  # Keep wheel/gesture direction conventional in GNOME. Niri has the matching
  # compositor-level policy in dotfiles/niri/config.kdl.
  home-manager.users.mariano.dconf.settings = {
    "org/gnome/desktop/peripherals/mouse"."natural-scroll" = false;
    "org/gnome/desktop/peripherals/touchpad"."natural-scroll" = false;
  };

  xdg.portal.config.niri = {
    default = [
      "gnome"
      "gtk"
    ];
    "org.freedesktop.impl.portal.Access" = "gtk";
    "org.freedesktop.impl.portal.AppChooser" = "gtk";
    "org.freedesktop.impl.portal.Notification" = "gtk";
    "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
  };

  programs.dank-material-shell.greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/mariano";
    logs = {
      save = true;
      path = "/var/lib/dms-greeter/dms-greeter.log";
    };
  };

  # Firmware updates through LVFS. This laptop's config carries several
  # firmware-level workarounds (Wi-Fi ASPM, amdgpu display idle paths, s2idle),
  # and UEFI/EC/Wi-Fi firmware releases are the lever most likely to retire
  # them. Updates are never applied automatically: `fwupdmgr update` prompts.
  services.fwupd.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };
  systemd.services.bluetooth-rfkill-unblock = {
    description = "Unblock Bluetooth rfkill switches";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.util-linux}/bin/rfkill unblock bluetooth";
    };
  };
  system.activationScripts.bluetoothRfkillUnblock.text = ''
    ${pkgs.util-linux}/bin/rfkill unblock bluetooth || true
  '';

  services.input-remapper.enable = true;
  hardware.opentabletdriver.enable = true;
  hardware.uinput.enable = true;
  boot.kernelModules = [ "uinput" ];

  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        alt = {
          d = "pagedown";
          left = "home";
          right = "end";
          u = "pageup";
        };
        "control+alt" = { };
      };
    };
  };

  environment.etc."libinput/local-overrides.quirks".text = ''
    [Logitech MX Master 4 Bluetooth high-resolution wheel]
    MatchUdevType=mouse
    MatchBus=bluetooth
    MatchVendor=0x046D
    MatchProduct=0xB042
    AttrEventCode=-REL_WHEEL_HI_RES;-REL_HWHEEL_HI_RES
  '';

  services.xserver.xkb = {
    layout = "us,es";
    variant = ",";
    options = "grp:shift_caps_toggle";
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.systemPackages = with pkgs; [
    bluez-tools
    pciutils
    usbutils
  ];
}
