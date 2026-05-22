{ pkgs, ... }:

{
  programs.firefox.enable = true;
  programs.appimage.enable = true;
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
  };

  xdg.mime.defaultApplications = {
    "text/html" = "brave-browser.desktop";
    "x-scheme-handler/http" = "brave-browser.desktop";
    "x-scheme-handler/https" = "brave-browser.desktop";
    "x-scheme-handler/about" = "brave-browser.desktop";
    "x-scheme-handler/unknown" = "brave-browser.desktop";
    "application/pdf" = "firefox.desktop";
  };

  xdg.terminal-exec = {
    enable = true;
    settings = {
      KDE = [ "com.mitchellh.ghostty.desktop" ];
      default = [ "com.mitchellh.ghostty.desktop" ];
    };
  };

  environment.etc."xdg/kdeglobals".text = ''
    [General]
    TerminalApplication=ghostty
    TerminalService=com.mitchellh.ghostty.desktop
  '';

  services.flatpak.enable = true;
  services.packagekit.enable = true;

  environment.systemPackages = with pkgs; [
    brave
    spotify
    slack
    obsidian
    localsend
    mpv
    qbittorrent
    onlyoffice-desktopeditors
    kdePackages.discover
    kdePackages.kdenlive
    krita
    inkscape
    gimp
  ];
}
