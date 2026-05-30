{ lib, pkgs, ... }:

let
  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
in
{
  services.xserver.enable = true;

  services.displayManager.sddm.enable = false;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sessionPackages = lib.mkForce [ pkgs.niri ];

  users.groups.greeter = { };
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    home = "/var/lib/dms-greeter";
  };

  services.greetd.settings.default_session.user = "greeter";
  security.pam.services.greetd.allowNullPassword = lib.mkForce false;
  systemd.services.greetd.environment = {
    DMS_GREET_REMEMBER_LAST_SESSION = "0";
    DMS_SAVE_SESSION = "false";
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

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };
  services.blueman.enable = true;

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

  system.activationScripts.kdeShortcuts.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config

    ${kwriteconfig} --file /home/mariano/.config/kglobalshortcutsrc --group kwin --key "Window Close" "Alt+F4,Alt+F4,Close Window"
    ${kwriteconfig} --file /home/mariano/.config/kglobalshortcutsrc --group kwin --key "Window Fullscreen" "Alt+F11,Alt+F11,Make Window Fullscreen"
    ${kwriteconfig} --file /home/mariano/.config/kdeglobals --group KDE --key AnimationDurationFactor 0

    chown mariano:users /home/mariano/.config/kglobalshortcutsrc
    chown mariano:users /home/mariano/.config/kdeglobals
  '';

  environment.systemPackages = with pkgs; [
    blueman
    bluez-tools
    pciutils
    usbutils
    kdePackages.kconfig
    kdePackages.ksshaskpass
  ];
}
