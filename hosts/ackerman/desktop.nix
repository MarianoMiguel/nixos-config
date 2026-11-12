# ackerman's desktop, the M5 Max's part: niri on the GPU (rendering on renderD128, scanout on
# simpledrm until the display driver lands; GL native or on zink, below) and the login at the
# console (tty1): niri starts after a 3 s prompt (s = a shell, z = this session on zink). The
# session itself, stock niri with stock DMS (Mariano, 2026-11-09), is session.nix; the input
# comforts are comfort.nix.
#
# The GL driver. Aurora's Mesa (packages/mesa-aurora.nix) has native Gallium GL for the M5 Max
# (#194, #256-#258) and still has zink over the Asahi Vulkan driver, which ackerman ran from
# 2026-11-08 to 11-12. Native has never run on a G17C (rolotrealanis98's results are on the G17S;
# Erik's M5 Max desktop is on zink), so zink is one switch away, three ways:
#   - for good: ackerman.gl.driver = "zink" (the system's default, "native" unless set);
#   - without a rebuild: `ackerman-gl zink` (writes ~/.config/ackerman/gl; `ackerman-gl default`
#     removes it, `ackerman-gl` shows what the next session gets), then log out and in;
#   - for one session: `z` at the tty1 prompt, or `ACKERMAN_GL=zink niri-session-ackerman`.
# The choice is made once, when niri-session-ackerman starts, and reaches every client through the
# session's environment (MESA_LOADER_DRIVER_OVERRIDE=zink, or unset for native). Shells outside the
# session (SSH, the console) don't get it: run `MESA_LOADER_DRIVER_OVERRIDE=zink <program>` there.
{
  config,
  lib,
  pkgs,
  pkgsUnstable,
  ...
}:

let
  cfg = config.ackerman.gl;
  mesa = pkgs.callPackage ./packages/mesa-aurora.nix { };

  # ACKERMAN_GL, else ~/.config/ackerman/gl, else ackerman.gl.driver
  glTool = pkgs.writeShellScriptBin "ackerman-gl" ''
    file="''${XDG_CONFIG_HOME:-$HOME/.config}/ackerman/gl"
    default=${cfg.driver}
    resolve() {
      if [ -n "''${ACKERMAN_GL:-}" ]; then
        mode=$ACKERMAN_GL from="ACKERMAN_GL"
      elif [ -r "$file" ]; then
        read -r mode < "$file" || true
        from="$file"
      else
        mode=$default from="ackerman.gl.driver (the system's default)"
      fi
      case "$mode" in
        native | zink) ;;
        *)
          echo "ackerman-gl: '$mode' from $from is neither native nor zink; using $default" >&2
          mode=$default from="ackerman.gl.driver (the system's default)"
          ;;
      esac
    }
    case "''${1:-}" in
      "")
        resolve
        echo "The next session's GL: $mode (from $from)"
        ;;
      mode)
        resolve
        echo "$mode"
        ;;
      native | zink)
        mkdir -p "$(dirname "$file")"
        echo "$1" > "$file"
        echo "The next session's GL: $1 ($file). Log out and in (or restart niri-session-ackerman)."
        ;;
      default)
        rm -f "$file"
        echo "The next session's GL: $default (ackerman.gl.driver)"
        ;;
      *)
        echo "usage: ackerman-gl [native | zink | default | mode]" >&2
        exit 2
        ;;
    esac
  '';
  # The Arch daily's niri, 26.04, from pkgsUnstable. Patched as on the niri desktop, so
  # Mod+Shift+left-drag resizes (no right button on a trackpad).
  niri = (import ../../overlays/niri-mod-shift-drag-resize.nix pkgsUnstable pkgsUnstable).niri;

  session = pkgs.writeShellScriptBin "niri-session-ackerman" ''
    export XCURSOR_THEME=Adwaita XCURSOR_SIZE=24
    export QT_QPA_PLATFORM="wayland;xcb" ELECTRON_OZONE_PLATFORM_HINT=wayland MOZ_ENABLE_WAYLAND=1
    log=$HOME/.cache/niri-session.log
    mkdir -p "$HOME/.cache"; [ -f "$log" ] && mv -f "$log" "$log.old"
    # The GL driver for this session (ackerman-gl), into the systemd user manager as well:
    # niri-session imports the environment into it, but an import never removes a variable, and
    # an earlier session may have left zink there
    gl=$(${glTool}/bin/ackerman-gl mode)
    # ACKERMAN_GL is for this start only: kept, the session's terminals would report it as the choice
    unset ACKERMAN_GL
    systemctl --user unset-environment ACKERMAN_GL 2>/dev/null
    if [ "$gl" = zink ]; then
      export MESA_LOADER_DRIVER_OVERRIDE=zink
    else
      unset MESA_LOADER_DRIVER_OVERRIDE
      systemctl --user unset-environment MESA_LOADER_DRIVER_OVERRIDE 2>/dev/null
    fi
    echo "niri-session-ackerman $(date -Is): Mesa ${mesa.version}, GL $gl" > "$log"
    # niri reads ~/.config/niri/config.kdl. A NIRI_CONFIG left in the user manager by an earlier
    # session (the niri + Folio days set one) would win over it: niri.service starts from there.
    unset NIRI_CONFIG
    systemctl --user unset-environment NIRI_CONFIG 2>/dev/null
    exec ${niri}/bin/niri-session >> "$log" 2>&1
  '';
in
{
  options.ackerman.gl.driver = lib.mkOption {
    type = lib.types.enum [
      "native"
      "zink"
    ];
    default = "native";
    description = ''
      The GL driver niri and its clients use: "native" (Aurora's Gallium driver) or "zink" (GL over
      the Asahi Vulkan driver, as ackerman ran until 2026-11-12). A session can still choose the
      other without a rebuild (`ackerman-gl`, ~/.config/ackerman/gl, or ACKERMAN_GL).
    '';
  };

  config = {
    hardware.graphics = {
      enable = true;
      package = mesa;
    };
    # All of /share in the system profile, as on bonhart (its desktop modules link it)
    environment.pathsToLink = [ "/share" ];
    # No GL variables here: MESA_LOADER_DRIVER_OVERRIDE is the session's (niri-session-ackerman), so
    # that the login shell niri-session re-runs can't put it back. ASAHI_M5_BRINGUP is gone: since
    # #205 the M5 Max (G17C, chip 0x6050, four clusters) is admitted on exactly the identity the
    # bring-up switch checked, so it changes nothing here.

    programs.niri = {
      enable = true;
      package = niri;
    };

    # tty1: a 3 s prompt, then niri (s = stay in the shell, z = this session's GL on zink). Twice guarded against re-entry: niri's
    # session re-runs the login shell, and a crashed session must not loop. Bash and zsh (his login
    # shell) both read this; their `read` differ.
    environment.loginShellInit = ''
      if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$NIRI_SOCKET" ] && [ -z "$ACKERMAN_SESSION" ]; then
        export ACKERMAN_SESSION=1
        printf 'ackerman: niri in 3 s (s = shell, z = GL on zink this time) '
        if [ -n "''${ZSH_VERSION-}" ]; then
          read -r -t 3 -k 1 k || k=
        else
          read -r -t 3 -n 1 k || k=
        fi
        echo
        if [ "$k" = z ]; then
          ACKERMAN_GL=zink ${session}/bin/niri-session-ackerman
          echo "niri exited (status $?). Log: ~/.cache/niri-session.log. 'niri-session-ackerman' starts it again."
        elif [ "$k" != s ]; then
          ${session}/bin/niri-session-ackerman
          echo "niri exited (status $?). Log: ~/.cache/niri-session.log. 'niri-session-ackerman' starts it again;"
          echo "if native GL drew nothing: 'ackerman-gl zink' (or z at this prompt next time)."
        fi
      fi
    '';

    services.gnome.gnome-keyring.enable = true;
    security.polkit.enable = true;
    services.upower.enable = true;
    services.power-profiles-daemon.enable = false;
    # DMS's Settings are the Bluetooth surface; no Blueman tray beside them.
    hardware.bluetooth.enable = true;

    fonts.packages = with pkgs; [
      inter
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
      nerd-fonts.symbols-only
      ibm-plex
      font-awesome
    ];

    environment.systemPackages = [
      session
      glTool
    ]
    ++ (with pkgs; [
      alacritty
      foot
      kitty
      firefox
      chromium
      nautilus
      evince
      imv
      mpv
      fuzzel
      grim
      slurp
      wl-clipboard
      cliphist
      brightnessctl
      xwayland-satellite
      adwaita-icon-theme
      papirus-icon-theme
      vulkan-tools
      mesa-demos
      glmark2
      wayland-utils
      libinput
      evtest
    ]);
  };
}
