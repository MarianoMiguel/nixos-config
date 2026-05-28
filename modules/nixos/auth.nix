{ lib, pkgs, ... }:

let
  yubikeyOnlyPamServices = [
    "greetd"
    "i3lock"
    "i3lock-color"
    "kde"
    "login"
    "polkit-1"
    "su"
    "sudo"
    "swaylock"
    "systemd-run0"
    "vlock"
    "xlock"
    "xscreensaver"
  ];
in

{
  programs.yubikey-manager.enable = true;

  security.pam.u2f = {
    control = "sufficient";
    settings = {
      cue = true;
      userpresence = 1;
    };
  };

  security.pam.services = lib.genAttrs yubikeyOnlyPamServices (_: {
    u2fAuth = true;
    unixAuth = false;
  });

  environment.systemPackages = with pkgs; [
    pam_u2f
    yubico-piv-tool
  ];
}
