{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      curl
      expat
      fontconfig
      freetype
      glib
      icu
      libGL
      libxkbcommon
      openssl
      sqlite
      stdenv.cc.cc
      zlib
    ];
  };

  environment.systemPackages = with pkgs; [
    ghostty
    vim

    nodejs_22
    nodePackages.npm
    python3
    python3Packages.pip
    uv
    mise

    gh
    docker
    docker-compose

    git
    curl
    wget
    unzip
    ripgrep
    fd
    fzf
    jq
    wl-clipboard
    bat
    eza
    fastfetch
    btop
    gcc
    gnumake
    tree-sitter
    lua-language-server
    stylua
  ];
}
