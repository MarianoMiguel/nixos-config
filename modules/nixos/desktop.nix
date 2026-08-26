{ pkgs, ... }:

let
  catppuccinGtk = pkgs.catppuccin-gtk.override {
    variant = "mocha";
    accents = [ "mauve" ];
  };
in
{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "gnome";
  services.desktopManager.gnome.enable = true;

  # Keep wheel and gesture direction conventional in the only desktop session.
  home-manager.users.mariano.dconf.settings = {
    "org/gnome/desktop/peripherals/mouse"."natural-scroll" = false;
    "org/gnome/desktop/peripherals/touchpad"."natural-scroll" = false;
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-animations = true;
      gtk-theme = "catppuccin-mocha-mauve-standard";
      icon-theme = "Adwaita";
    };
  };

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
    catppuccinGtk
    pciutils
    usbutils
  ];
}
