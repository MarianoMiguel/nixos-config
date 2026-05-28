{ pkgs, ... }:

{
  programs.yubikey-manager.enable = true;

  security.pam.u2f = {
    control = "sufficient";
    settings = {
      cue = true;
      nouserok = true;
      userpresence = 1;
    };
  };

  security.pam.services.greetd.u2fAuth = true;

  environment.systemPackages = with pkgs; [
    pam_u2f
    yubico-piv-tool
  ];
}
