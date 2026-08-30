{ lib, pkgs, ... }:

let
  manifestoDocument = ../../assets/manifesto.md;

  manifesto = pkgs.writeShellApplication {
    name = "manifesto";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glow
      pkgs.less
      pkgs.ncurses
    ];
    text = ''
      columns="$(tput cols 2>/dev/null || printf '92')"
      if [ "$columns" -lt 68 ]; then
        render_width="$columns"
      elif [ "$columns" -gt 94 ]; then
        render_width=94
      else
        render_width="$columns"
      fi

      # Glow provides a calm, readable Markdown treatment; Ghostty supplies
      # the active ThemePort palette, translucency, padding, and backdrop.
      export PAGER="less -R -F -X"
      exec glow \
        --style dark \
        --preserve-new-lines \
        --width "$render_width" \
        --pager \
        ${lib.escapeShellArg (toString manifestoDocument)}
    '';
  };

  manifestoWindow = pkgs.writeShellApplication {
    name = "manifesto-window";
    runtimeInputs = [
      pkgs.ghostty
      manifesto
    ];
    text = ''
      exec ghostty \
        --class=mariano.manifesto \
        --title="Manifesto" \
        --font-size=13 \
        --window-padding-x=22 \
        --window-padding-y=18 \
        -e manifesto
    '';
  };
in
{
  environment.systemPackages = [
    manifesto
    manifestoWindow
  ];
}
