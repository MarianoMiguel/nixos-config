{ pkgs, ... }:

let
  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
in
{
  services.xserver.enable = true;

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.input-remapper.enable = true;
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        alt = {
          q = "A-f4";
          w = "A-f4";
          enter = "A-f11";
        };
      };
    };
  };

  services.xserver.xkb = {
    layout = "us,es";
    variant = ",";
    options = "grp:alt_shift_toggle";
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
    kdePackages.kconfig
  ];
}
