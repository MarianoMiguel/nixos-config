{ lib, pkgs, ... }:

let
  luksRootDevice = "luks-7cdf3e08-99fb-4ac5-9480-f0c6c662cbd2";

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
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.fido2.enable = true;
  boot.initrd.luks.devices.${luksRootDevice}.crypttabExtraOpts = [
    "fido2-device=auto"
  ];

  programs.yubikey-manager.enable = true;

  security.pam.u2f = {
    control = "sufficient";
    settings = {
      authfile = "/etc/u2f-mappings";
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
