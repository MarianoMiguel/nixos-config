{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.zsh;

  users.users.mariano = {
    isNormalUser = true;
    description = "Mariano";
    extraGroups = [
      "docker"
      "input"
      "lp"
      "networkmanager"
      "scanner"
      "uinput"
      "video"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  programs.zsh = {
    enable = true;
  };
}
