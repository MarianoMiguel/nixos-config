{ pkgs, ... }:

{
  services.xserver.enable = true;

  services.displayManager.sddm.enable = false;
  # GNOME is the only desktop session (gnome.nix adds its extensions). Plasma,
  # Blueman, NetworkManager's tray applet, Discover and PackageKit stay out as
  # competing control surfaces. The login screen is login-screen.nix.
  services.desktopManager.gnome.enable = true;

  # Keep wheel/gesture direction conventional.
  home-manager.users.mariano.dconf.settings = {
    "org/gnome/desktop/peripherals/mouse"."natural-scroll" = false;
    "org/gnome/desktop/peripherals/touchpad"."natural-scroll" = false;
    # Interstellar's window lights sit at the start of the title bar: close,
    # then maximize (niri has no minimize). GTK apps read this through the
    # settings portal, Chrome straight from dconf; themeport draws the lights.
    "org/gnome/desktop/wm/preferences"."button-layout" = "close,maximize:";
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
        # Super is left alone so a tap reaches GNOME as the Activities key.
        # (Under niri, leftmeta was oneshot(meta): on a fast Super+digit chord
        # the keyboard reports Super's release before the digit. oneshot also
        # swallowed a bare tap, which GNOME needs.)
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
    # compose:ralt: Right Alt then two keys types accents and symbols on the
    # US layout without switching to the Spanish one.
    options = "grp:shift_caps_toggle,compose:ralt";
  };

  # Qt applications use the KDE platform theme and Breeze so they read
  # Themeport's rendered ~/.config/kdeglobals for colours, fonts and icons.
  # The former gtk3 platform theme only carried GTK's base palette, which is
  # why KDE apps stayed light while the desktop was dark.
  # Clients that predate the cursor-shape protocol (Xwayland, some Electron
  # builds) read these; everything else takes the compositor cursor, so the
  # pointer looks the same in every window.
  environment.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
    # Interstellar's Qt title bar (packages/qt-interstellar-decorations) for
    # every Qt app, also those D-Bus or a service starts.
    QT_WAYLAND_DECORATION = "interstellar";
  };

  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
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
    # Qt apps (Dolphin, Kate, qBittorrent, OBS...) draw Interstellar's title
    # bar with this QtWayland decoration plugin: two lights at the start like
    # the GTK apps', the theme's colours from themeport. Qt finds it through
    # the qt module's QT_PLUGIN_PATH (/run/current-system/sw/lib/qt-6/plugins);
    # QT_WAYLAND_DECORATION above selects it. GNOME draws no server-side
    # decorations, so every Qt window gets it.
    (callPackage ../../packages/qt-interstellar-decorations { })
  ];
}
