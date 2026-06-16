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

    nodejs_24
    nodePackages.npm
    python3
    python3Packages.pip
    uv
    mise

    gh
    git-lfs
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
    duf
    file
    gcc
    gnumake
    pkg-config
    openssl
    tree-sitter
    lua-language-server
    stylua
  ];
}
