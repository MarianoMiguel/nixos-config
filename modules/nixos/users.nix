{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.zsh;

  users.users.mariano = {
    isNormalUser = true;
    description = "Mariano";
    extraGroups = [
      "lp"
      "networkmanager"
      "scanner"
      "uinput"
      "video"
      "wheel"
      "ydotool"
    ];
    packages = with pkgs; [
      kdePackages.kate
    ];
    # The MacBook, so it can reach this machine over the tailnet (deploys, Overfly).
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINf1PihwqTD8d7wAIOrrvYS/HJPlELAb8FAsGVvPVWS8 mariano@macbook"
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
