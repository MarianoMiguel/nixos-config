{ codex-desktop-linux, granola-linux, lib, pkgs, pkgsUnstable, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  defaultBrowserDesktop = "google-chrome.desktop";
  browserMimeTypes = [
    "text/html"
    "text/xml"
    "application/xhtml+xml"
    "application/xml"
    "application/rss+xml"
    "application/rdf+xml"
    "x-scheme-handler/about"
    "x-scheme-handler/chrome"
    "x-scheme-handler/ftp"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/unknown"
    "x-scheme-handler/webcal"
  ];
  browserMimeDefaults = lib.genAttrs browserMimeTypes (_: defaultBrowserDesktop);
  browserMimeAssociations = lib.genAttrs browserMimeTypes (_: [ defaultBrowserDesktop ]);
  braveMimeAssociations = lib.genAttrs browserMimeTypes (_: [
    "brave-browser.desktop"
    "com.brave.Browser.desktop"
  ]);
  zedEditorWithCli = pkgs.symlinkJoin {
    name = "zed-editor-with-zed-cli";
    paths = [ pkgs.zed-editor ];
    postBuild = ''
      if [ ! -e "$out/bin/zed" ]; then
        ln -s ${pkgs.zed-editor}/bin/zeditor "$out/bin/zed"
      fi
    '';
  };
  davinciResolve = pkgs.symlinkJoin {
    name = "davinci-resolve-with-rusticl";
    paths = [ pkgsUnstable.davinci-resolve ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/davinci-resolve \
        --set OCL_ICD_VENDORS ${pkgs.mesa.opencl}/etc/OpenCL/vendors \
        --set RUSTICL_ENABLE radeonsi
    '';
  };
  herdrVersion = "0.7.5";
  herdr = pkgs.stdenvNoCC.mkDerivation {
    pname = "herdr";
    version = herdrVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${herdrVersion}/herdr-linux-x86_64";
      hash = "sha256-PcgyiAc+TC08Z5ow576XvMqRQcb9F9u7khkULpXFklM=";
    };
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/herdr"
      runHook postInstall
    '';
    meta = {
      description = "Terminal workspace manager for AI coding agents";
      homepage = "https://herdr.dev/";
      license = lib.licenses.asl20;
      mainProgram = "herdr";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
  obsbotCameraControl = pkgs.callPackage ../../packages/obsbot-camera-control.nix { };
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
  figmaDesktopVersion = "126.5.6";
  figmaDesktopPname = "figma-desktop";
  figmaDesktopSrc = pkgs.fetchurl {
    url = "https://github.com/IliyaBrook/figma-linux/releases/download/${figmaDesktopVersion}/figma-desktop-${figmaDesktopVersion}-amd64.AppImage";
    hash = "sha256-SLn4y+NVCcBDZrGqIpmpIEQavY7xngt5JMI8yG1g6/0=";
  };
  figmaDesktopContents = pkgs.appimageTools.extract {
    pname = figmaDesktopPname;
    version = figmaDesktopVersion;
    src = figmaDesktopSrc;
    postExtract = ''
      substituteInPlace $out/AppRun \
        --replace-fail 'integrate_desktop 2>/dev/null || true' \
        ': # Desktop integration is managed by NixOS'
    '';
  };
  figmaDesktop = pkgs.appimageTools.wrapAppImage {
    pname = figmaDesktopPname;
    version = figmaDesktopVersion;
    src = figmaDesktopContents;

    extraInstallCommands = ''
      install -Dm0444 \
        ${figmaDesktopContents}/io.github.nickvdp.figma-desktop-linux.desktop \
        $out/share/applications/io.github.nickvdp.figma-desktop-linux.desktop
      install -Dm0444 \
        ${figmaDesktopContents}/io.github.nickvdp.figma-desktop-linux.png \
        $out/share/icons/hicolor/256x256/apps/io.github.nickvdp.figma-desktop-linux.png

      substituteInPlace \
        $out/share/applications/io.github.nickvdp.figma-desktop-linux.desktop \
        --replace-fail 'Exec=AppRun %u' 'Exec=${figmaDesktopPname} %u'
    '';

    meta = {
      description = "Patched Figma Desktop client for Linux";
      homepage = "https://github.com/IliyaBrook/figma-linux";
      license = lib.licenses.unfree;
      mainProgram = figmaDesktopPname;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
#   pencilDev = wrapDesignAppImage {
#     pname = "pencil-dev";
#     version = "1.1.57";
#     url = "https://www.pencil.dev/download/Pencil-linux-x86_64.AppImage";
#     hash = "sha256-nuf4jVPU5wsR1MwFXr0llAOGxQ4vwiQNEoiBwPwbAXQ=";
#     desktopFile = "pencil.desktop";
#     iconFile = "pencil.png";
#     description = "Vector design canvas that lives alongside code";
#     homepage = "https://www.pencil.dev/";
#   };
in

{
  programs.firefox.enable = true;
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
  };

  xdg.mime.defaultApplications = browserMimeDefaults // {
    "application/pdf" = "firefox.desktop";
    "x-scheme-handler/figma" = "io.github.nickvdp.figma-desktop-linux.desktop";
    "x-scheme-handler/granola" = "granola.desktop";
    "x-scheme-handler/granola-dev" = "granola.desktop";
    # "x-scheme-handler/pencil" = "pencil.desktop";
  };
  xdg.mime.addedAssociations = browserMimeAssociations;
  xdg.mime.removedAssociations = braveMimeAssociations;

  xdg.terminal-exec = {
    enable = true;
    settings = {
      KDE = [ "com.mitchellh.ghostty.desktop" ];
      default = [ "com.mitchellh.ghostty.desktop" ];
    };
  };

  environment.etc."xdg/kdeglobals".text = ''
    [General]
    BrowserApplication=${defaultBrowserDesktop}
    TerminalApplication=ghostty
    TerminalService=com.mitchellh.ghostty.desktop
  '';

  # Chrome's local GenAI model is currently a 4 GiB component and can stall
  # browser startup while it is loaded. This browser-level policy prevents the
  # model from being downloaded and makes Chrome remove an existing copy.
  environment.etc."opt/chrome/policies/managed/disable-local-genai-model.json".text =
    builtins.toJSON {
      GenAILocalFoundationalModelSettings = 1;
    };

  environment.sessionVariables = {
    BROWSER = "google-chrome-stable";
    DEFAULT_BROWSER = defaultBrowserDesktop;
  };

  services.flatpak.enable = true;
  services.packagekit.enable = true;

  environment.systemPackages = with pkgs; [
    brave
    google-chrome
    spotify
    slack
    lmstudio
    obsidian
    fluent-reader
    obsbotCameraControl
    figmaDesktop
    vscode
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
    rapidraw
    freecad
    orca-slicer
    # pencilDev
  ] ++ [
    davinciResolve
    codex-desktop-linux.packages.${system}.codex-desktop
    granola-linux.packages.${system}.default
    herdr
  ];
}
