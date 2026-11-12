# ackerman's desktop, the M5 Max's part: niri on the GPU (GL on zink over the Asahi Vulkan driver,
# rendering on renderD128, scanout on simpledrm until the display driver lands) and the login at
# the console (tty1): niri starts after a 3 s prompt (s = a shell). The session itself, stock niri
# with stock DMS (Mariano, 2026-11-09), is session.nix; the input comforts are comfort.nix.
{
  pkgs,
  pkgsUnstable,
  ...
}:

let
  mesa = pkgs.callPackage ./packages/mesa-aurora.nix { };
  # The Arch daily's niri, 26.04, from pkgsUnstable. Patched as on the niri desktop, so
  # Mod+Shift+left-drag resizes (no right button on a trackpad).
  niri = (import ../../overlays/niri-mod-shift-drag-resize.nix pkgsUnstable pkgsUnstable).niri;

  session = pkgs.writeShellScriptBin "niri-session-ackerman" ''
    export XCURSOR_THEME=Adwaita XCURSOR_SIZE=24
    export QT_QPA_PLATFORM="wayland;xcb" ELECTRON_OZONE_PLATFORM_HINT=wayland MOZ_ENABLE_WAYLAND=1
    log=$HOME/.cache/niri-session.log
    mkdir -p "$HOME/.cache"; [ -f "$log" ] && mv -f "$log" "$log.old"
    echo "niri-session-ackerman $(date -Is): Mesa ${mesa.version}" > "$log"
    # niri reads ~/.config/niri/config.kdl. A NIRI_CONFIG left in the user manager by an earlier
    # session (the niri + Folio days set one) would win over it: niri.service starts from there.
    unset NIRI_CONFIG
    systemctl --user unset-environment NIRI_CONFIG 2>/dev/null
    exec ${niri}/bin/niri-session >> "$log" 2>&1
  '';
in
{
  hardware.graphics = {
    enable = true;
    package = mesa;
  };
  # All of /share in the system profile, as on bonhart (its desktop modules link it)
  environment.pathsToLink = [ "/share" ];
  environment.sessionVariables = {
    # G17 (M5) is admitted only on this opt-in; GL and GLES run on zink over the Vulkan driver
    ASAHI_M5_BRINGUP = "1";
    MESA_LOADER_DRIVER_OVERRIDE = "zink";
  };

  programs.niri = {
    enable = true;
    package = niri;
  };

  # tty1: a 3 s prompt, then niri (s = stay in the shell). Twice guarded against re-entry: niri's
  # session re-runs the login shell, and a crashed session must not loop. Bash and zsh (his login
  # shell) both read this; their `read` differ.
  environment.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$NIRI_SOCKET" ] && [ -z "$ACKERMAN_SESSION" ]; then
      export ACKERMAN_SESSION=1
      printf 'ackerman: niri in 3 s (s = shell) '
      if [ -n "''${ZSH_VERSION-}" ]; then
        read -r -t 3 -k 1 k || k=
      else
        read -r -t 3 -n 1 k || k=
      fi
      echo
      if [ "$k" != s ]; then
        ${session}/bin/niri-session-ackerman
        echo "niri exited (status $?). Log: ~/.cache/niri-session.log. 'niri-session-ackerman' starts it again."
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

  environment.systemPackages =
    [ session ]
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
}
