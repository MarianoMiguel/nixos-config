{ pkgs, ... }:

{
  programs.firefox.enable = true;
  programs.appimage.enable = true;

  xdg.mime.defaultApplications = {
    "text/html" = "brave-browser.desktop";
    "x-scheme-handler/http" = "brave-browser.desktop";
    "x-scheme-handler/https" = "brave-browser.desktop";
    "x-scheme-handler/about" = "brave-browser.desktop";
    "x-scheme-handler/unknown" = "brave-browser.desktop";
  };

  services.flatpak.enable = true;
  services.packagekit.enable = true;

  environment.systemPackages = with pkgs; [
    brave
    spotify
    slack
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
