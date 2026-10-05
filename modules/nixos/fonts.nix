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
          "IBM Plex Mono"
          "GeistMono Nerd Font"
          "JetBrainsMono Nerd Font"
        ];
        sansSerif = [
          "Inter"
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
