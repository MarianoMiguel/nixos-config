{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  system.activationScripts.nvimConfig.text = ''
    rm -rf /home/mariano/.config/nvim
    mkdir -p /home/mariano/.config/nvim
    cp -R ${../../dotfiles/nvim}/. /home/mariano/.config/nvim/
    chown -R mariano:users /home/mariano/.config/nvim
    chmod -R u+w /home/mariano/.config/nvim
  '';

  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  environment.systemPackages = with pkgs; [
    neovim
  ];
}
