{ pkgs, ... }:

{
  users.users.mariano = {
    isNormalUser = true;
    description = "Mariano";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
}
