{ figma-linux-font-helper, pkgs, ... }:

let
  figmaLinux = pkgs.figma-linux.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      main_js="$out/share/figma-linux/resources/app/main/main.js"
      substituteInPlace "$main_js" \
        --replace-fail 'return e.app.emit("focusLastWindow"),void e.app.quit();' 'return void e.app.quit();' \
        --replace-fail 'setTimeout((()=>{""!==t&&this.windowManager.openUrl(t)}),1500)' 'setTimeout((()=>{""!==t&&(this.windowManager.tryHandleAppAuthRedeemUrl(t)||this.windowManager.openUrl(t))}),1500)'
      '';
  });
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
}
