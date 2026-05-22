{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  systemd.tmpfiles.rules = [
    "d /home/mariano/.config 0755 mariano users - -"
    "L+ /home/mariano/.config/nvim - - - - ${../../dotfiles/nvim}"
  ];

  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  environment.systemPackages = with pkgs; [
    neovim
  ];
}
