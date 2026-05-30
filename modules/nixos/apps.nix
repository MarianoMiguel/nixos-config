{ codex-desktop-linux, lib, pkgs, ... }:

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

  xdg.mime.defaultApplications = browserMimeDefaults // {
    "application/pdf" = "firefox.desktop";
    "x-scheme-handler/paper" = "paper-desktop.desktop";
    "x-scheme-handler/paper-dev" = "paper-desktop.desktop";
    "x-scheme-handler/pencil" = "pencil.desktop";
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

  environment.sessionVariables = {
    BROWSER = "google-chrome-stable";
    DEFAULT_BROWSER = defaultBrowserDesktop;
  };

  system.activationScripts.chromeDefaultBrowser.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config

    for mime in ${lib.escapeShellArgs browserMimeTypes}; do
      ${pkgs.util-linux}/bin/runuser -u mariano -- env \
        HOME=/home/mariano \
        XDG_CONFIG_HOME=/home/mariano/.config \
        ${pkgs.xdg-utils}/bin/xdg-mime default ${defaultBrowserDesktop} "$mime"
    done

    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
      --file /home/mariano/.config/kdeglobals \
      --group General \
      --key BrowserApplication \
      ${defaultBrowserDesktop}
    chown mariano:users /home/mariano/.config/kdeglobals

    mimeapps=/home/mariano/.config/mimeapps.list
    if [ -f "$mimeapps" ]; then
      tmp="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.gawk}/bin/awk \
        -v browser="${defaultBrowserDesktop}" \
        -v browser_mimes="${lib.concatStringsSep " " browserMimeTypes}" '
        BEGIN {
          count = split(browser_mimes, mimes, " ");
          for (i = 1; i <= count; i++) {
            browser_mime[mimes[i]] = 1;
          }
          section = "";
        }

        /^\[/ {
          section = $0;
        }

        section == "[Added Associations]" && index($0, "=") {
          key = $0;
          sub(/=.*/, "", key);
          if (key in browser_mime) {
            print key "=" browser ";";
            next;
          }
        }

        { print }
      ' "$mimeapps" > "$tmp"
      install -m 0644 -o mariano -g users "$tmp" "$mimeapps"
      rm -f "$tmp"
    fi
  '';

  services.flatpak.enable = true;
  services.packagekit.enable = true;

  environment.systemPackages = with pkgs; [
    brave
    google-chrome
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
