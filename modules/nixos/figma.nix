{ figma-linux-font-helper, pkgs, ... }:

let
  desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
  figmaBraveAppId = "mcjdlkonbhobpbhflaaeilimpiandlci";
  figmaLinux = pkgs.figma-linux.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      main_js="$out/share/figma-linux/resources/app/main/main.js"
      substituteInPlace "$main_js" \
        --replace-fail 'return e.app.emit("focusLastWindow"),void e.app.quit();' 'return void e.app.quit();' \
        --replace-fail 'setTimeout((()=>{""!==t&&this.windowManager.openUrl(t)}),1500)' 'setTimeout((()=>{""!==t&&(this.windowManager.tryHandleAppAuthRedeemUrl(t)||this.windowManager.openUrl(t))}),1500)'
    '';
  });
  figmaBravePwaDesktop = pkgs.writeText "brave-${figmaBraveAppId}-Default.desktop" ''
    [Desktop Entry]
    Version=1.0
    Terminal=false
    Type=Application
    Name=Figma
    Exec=brave --profile-directory=Default --user-agent="${desktopUserAgent}" --app-id=${figmaBraveAppId}
    Icon=brave-${figmaBraveAppId}-Default
    StartupWMClass=crx_${figmaBraveAppId}
  '';
  figmaUrlHandlerDesktop = pkgs.writeTextDir "share/applications/figma-linux-url-handler.desktop" ''
    [Desktop Entry]
    Version=1.5
    Type=Application
    Name=Figma URL Handler
    Comment=Open Figma links in Figma Linux
    Exec=${figmaLinux}/bin/figma-linux %U
    Icon=figma-linux
    Terminal=false
    NoDisplay=true
    MimeType=x-scheme-handler/figma;
    Categories=Graphics;Network;
  '';

  fontHelper = pkgs.rustPlatform.buildRustPackage {
    pname = "figma-linux-font-helper";
    version = "0.1.8";

    src = figma-linux-font-helper;
    cargoHash = "sha256-rJgeD10oGVfEw0WWfHO2vaoAdOHoVVt60B3TWHZjpoo=";

    doCheck = false;
  };
in

{
  environment.systemPackages = with pkgs; [
    fontHelper
  ] ++ [
    figmaLinux
    figmaUrlHandlerDesktop
  ];

  xdg.mime.addedAssociations = {
    "x-scheme-handler/figma" = "figma-linux-url-handler.desktop";
  };

  xdg.mime.defaultApplications = {
    "x-scheme-handler/figma" = "figma-linux-url-handler.desktop";
  };

  systemd.user.services.figma-fonthelper = {
    description = "Font Helper for Figma";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${fontHelper}/bin/font_helper";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  system.activationScripts.figmaFontHelperConfig.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config/figma-linux
    ${pkgs.jq}/bin/jq -n \
      '{
        host: "127.0.0.1",
        port: "44950",
        app: {
          fontDirs: [
            "/run/current-system/sw/share/X11/fonts",
            "/run/current-system/sw/share/fonts",
            "/home/mariano/Fonts",
            "/home/mariano/.local/share/fonts",
            "/home/mariano/.fonts"
          ]
        }
      }' > /home/mariano/.config/figma-linux/settings.json
    chown mariano:users /home/mariano/.config/figma-linux/settings.json
    chmod 0644 /home/mariano/.config/figma-linux/settings.json
  '';

  system.activationScripts.figmaBravePwaDesktop.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.local/share/applications
    install -d -m 0755 -o mariano -g users /home/mariano/Desktop
    install -m 0644 -o mariano -g users ${figmaBravePwaDesktop} /home/mariano/.local/share/applications/brave-${figmaBraveAppId}-Default.desktop
    install -m 0755 -o mariano -g users ${figmaBravePwaDesktop} /home/mariano/Desktop/brave-${figmaBraveAppId}-Default.desktop
  '';
}
