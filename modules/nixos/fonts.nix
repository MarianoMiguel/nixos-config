{ lib, pkgs, ... }:

{
  fonts = {
    packages =
      (builtins.filter lib.isDerivation (builtins.attrValues pkgs.nerd-fonts))
      ++ (with pkgs; [
        geist-font
      ]);

    fontconfig = {
      enable = true;
      localConf = ''
        <dir>/home/mariano/Fonts</dir>
      '';
      defaultFonts = {
        monospace = [
          "GeistMono Nerd Font"
          "JetBrainsMono Nerd Font"
        ];
        sansSerif = [
          "Geist"
          "Noto Sans"
        ];
        serif = [
          "Noto Serif"
        ];
      };
    };
  };

  system.activationScripts.userFonts.text = ''
    ${pkgs.coreutils}/bin/install -d -m 0755 -o mariano -g users /home/mariano/Fonts
    ${pkgs.coreutils}/bin/install -d -m 0755 -o mariano -g users /home/mariano/.local/share

    if [ ! -e /home/mariano/.local/share/fonts ]; then
      ${pkgs.coreutils}/bin/ln -s /home/mariano/Fonts /home/mariano/.local/share/fonts
      ${pkgs.coreutils}/bin/chown -h mariano:users /home/mariano/.local/share/fonts
    fi
  '';
}
