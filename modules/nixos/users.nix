{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.zsh;

  users.users.mariano = {
    isNormalUser = true;
    description = "Mariano";
    extraGroups = [
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

  # Mariano intentionally uses a separate administrator password. With
  # `rootpw`, sudo authenticates against root instead of the invoking user.
  security.sudo.extraConfig = ''
    Defaults rootpw
  '';
}
