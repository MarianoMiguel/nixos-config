{ codex-desktop-linux, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  zedEditorWithCli = pkgs.symlinkJoin {
    name = "zed-editor-with-zed-cli";
    paths = [ pkgs.zed-editor ];
    postBuild = ''
      if [ ! -e "$out/bin/zed" ]; then
        ln -s ${pkgs.zed-editor}/bin/zeditor "$out/bin/zed"
      fi
    '';
  };
  wrapDesignAppImage =
    {
      pname,
      version,
      url,
      hash,
      desktopFile,
      iconFile,
      description,
      homepage,
    }:
    let
      src = pkgs.fetchurl {
        inherit url hash;
      };
      appimageContents = pkgs.appimageTools.extract {
        inherit pname version src;
      };
    in
    pkgs.appimageTools.wrapType2 {
      inherit pname version src;

      nativeBuildInputs = [ pkgs.makeWrapper ];

      extraInstallCommands = ''
        install -Dm0444 ${appimageContents}/${desktopFile} $out/share/applications/${desktopFile}
        install -Dm0444 ${appimageContents}/${iconFile} $out/share/pixmaps/${iconFile}

        substituteInPlace $out/share/applications/${desktopFile} \
          --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U'

        wrapProgram $out/bin/${pname} \
          --set FONTCONFIG_FILE /etc/fonts/fonts.conf \
          --add-flags "--no-sandbox \''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
      '';

      meta = {
        inherit description homepage;
        license = pkgs.lib.licenses.unfree;
        mainProgram = pname;
        platforms = [ "x86_64-linux" ];
        sourceProvenance = with pkgs.lib.sourceTypes; [ binaryNativeCode ];
      };
    };
  paperDesign = wrapDesignAppImage {
    pname = "paper-design";
    version = "0.3.1";
    url = "https://download.paper.design/linux/appImage";
    hash = "sha256-RwrexWyvJtK9RtsLSWiIn1TRCmJlh4aQtDLvLSJcKf4=";
    desktopFile = "paper-desktop.desktop";
    iconFile = "paper-desktop.png";
    description = "Design app for visuals, user interfaces, prototypes, and assets";
    homepage = "https://paper.design/";
  };
  pencilDev = wrapDesignAppImage {
    pname = "pencil-dev";
    version = "1.1.57";
    url = "https://www.pencil.dev/download/Pencil-linux-x86_64.AppImage";
    hash = "sha256-nuf4jVPU5wsR1MwFXr0llAOGxQ4vwiQNEoiBwPwbAXQ=";
    desktopFile = "pencil.desktop";
    iconFile = "pencil.png";
    description = "Vector design canvas that lives alongside code";
    homepage = "https://www.pencil.dev/";
  };
in

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
    "x-scheme-handler/paper" = "paper-desktop.desktop";
    "x-scheme-handler/paper-dev" = "paper-desktop.desktop";
    "x-scheme-handler/pencil" = "pencil.desktop";
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
    gearlever
    font-manager
    zedEditorWithCli
    localsend
    mpv
    qbittorrent
    onlyoffice-desktopeditors
    kdePackages.discover
    kdePackages.kdenlive
    krita
    inkscape
    gimp
    darktable
    paperDesign
    pencilDev
  ] ++ [
    codex-desktop-linux.packages.${system}.codex-desktop
  ];
}
