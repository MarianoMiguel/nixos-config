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

}
