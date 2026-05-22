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
