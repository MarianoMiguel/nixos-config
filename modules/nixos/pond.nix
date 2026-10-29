{
  config,
  lib,
  pkgs,
  pkgsPond,
  pond-interface,
  pond-vicinae,
  ...
}:

# Pond (github.com/bflycomputer) as a design reference for the workshop:
# `pond-preview` runs Pond's shell in a nested niri window with throwaway
# config and state, so its motion and screens can be compared live. Pond is
# not a login session; it was one from 2026-10-27 to 2026-10-28 and was
# dropped as not ready (workshop/README.md).
let
  cfg = config.mariano.pond;
  niri = config.programs.niri.package;

  pondFonts = pkgs.callPackage ../../packages/pond-fonts.nix { };
  pondVicinae = pkgs.callPackage ../../packages/pond-vicinae.nix {
    inherit pkgsPond;
    src = pond-vicinae;
  };
  # Pond targets Qt 6.12 and Quickshell 0.3.2; see packages/pond-interface.nix.
  pondInterface = pkgsPond.callPackage ../../packages/pond-interface.nix {
    src = pond-interface;
    vicinae = pondVicinae;
  };

  share = "${pondInterface}/share/pond-interface";

  # Pond's skel config.kdl plus our include. Copied (not linked) so its
  # relative includes resolve inside the preview's config directory.
  configKdl = pkgs.writeText "pond-config.kdl" ''
    ${builtins.readFile "${pond-interface}/config/niri/config.kdl"}

    // NixOS additions (modules/nixos/pond.nix).
    include "./nixos.kdl"
  '';

  # A preview must never lock, blank or hibernate the host it runs inside.
  previewKdl = pkgs.writeText "pond-preview.kdl" ''
    spawn-at-startup "${pondVicinae}/bin/vicinae" "server" "--replace"
  '';

  # Pond in a nested niri window from any running session, with its config,
  # state and Quickshell lookup isolated under a temporary directory.
  preview = pkgs.writeShellScriptBin "pond-preview" ''
    set -eu
    root=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/pond-preview.XXXXXX")
    dir=$root/config/pond/niri
    mkdir -p "$dir/cfg" "$root/xdg/quickshell" "$root/state"
    ln -s ${share}/config/niri/shell "$dir/shell"
    for default in ${share}/config/niri/cfg/*.kdl; do
      cat "$default" > "$dir/cfg/$(basename "$default")"
    done
    ln -s ${previewKdl} "$dir/nixos.kdl"
    cat ${configKdl} > "$dir/config.kdl"
    ln -s ${share}/shell "$root/xdg/quickshell/pond-shell"
    ln -s ${share}/lockscreen "$root/xdg/quickshell/pond-lockscreen"
    echo "pond-preview: $root" >&2

    export XDG_CONFIG_HOME=$root/config XDG_STATE_HOME=$root/state
    export XDG_CONFIG_DIRS="$root/xdg:''${XDG_CONFIG_DIRS:-/etc/xdg}"
    export POND_NIRI_CONFIG_DIR=$dir POND_PAM_SERVICE=login GTK_THEME=Adwaita:dark
    unset NIRI_SOCKET
    exec ${niri}/bin/niri --config "$dir/config.kdl"
  '';
in
{
  options.mariano.pond.enable = lib.mkEnableOption "pond-preview, Pond's shell in a nested niri window, as a design reference";

  config = lib.mkIf cfg.enable {
    system.build.pondPreview = preview;

    environment.systemPackages = with pkgs; [
      preview
      capitaine-cursors
      grim # scripts/workshop capture
      iw
      kitty
      wl-clipboard
      zenity
    ];

    # Pond's screens render with its own faces.
    fonts.packages = [
      pondFonts
      pondInterface
      pkgs.ibm-plex
      pkgs.jetbrains-mono
    ];
  };
}
