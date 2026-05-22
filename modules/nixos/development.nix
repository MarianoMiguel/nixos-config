{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ghostty
    vim

    nodejs_22
    nodePackages.npm

    gh

    git
    curl
    wget
    unzip
    ripgrep
    fd
    fzf
    jq
    bat
    eza
    gcc
    gnumake
    tree-sitter
    lua-language-server
    stylua
  ];
}
