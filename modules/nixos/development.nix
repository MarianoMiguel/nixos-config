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

  # Self-installing CLIs (Claude Code, and anything else that drops a binary
  # in ~/.local/bin) resolve ahead of system packages. home.sessionPath also
  # lists this, but its prepend hides behind the __HM_SESS_VARS_SOURCED guard,
  # which the graphical session inherits without the PATH that came with it;
  # this shellInit-level prepend applies to every login shell unconditionally.
  environment.localBinInPath = true;

  environment.systemPackages = with pkgs; [
    ghostty
    vim

    nodejs_24
    pnpm
    python3
    python3Packages.pip
    uv
    mise
    # Claude Code comes from the native installer in ~/.local/bin, which
    # keeps itself current; the nixpkgs claude-code package lags weeks
    # behind its release pace. localBinInPath below puts it on $PATH.
    (writeShellScriptBin "opencode" ''
      exec /home/mariano/.opencode/bin/opencode "$@"
    '')

    gh
    git-lfs
    docker
    docker-compose

    git
    # Encrypts the personal payload archive (scripts/create-personal-payload.sh).
    age
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
