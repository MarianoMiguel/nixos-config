{ config, lib, pkgs, quickshell, ... }:

# Folio, the desktop shell built in workshop/ (dotfiles/quickshell/folio).
# It runs instead of DMS, never beside it: folio-shell.service conflicts with
# dms.service, and `mariano-shell use folio|dms` switches between them and
# remembers the choice. DMS stays installed as the fallback, and takes over
# for the session when Folio keeps failing (folio-shell-fallback).
let
  cfg = config.mariano.folio;
  qs = quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  folio = pkgs.callPackage ../../packages/folio-shell.nix { };

  dmsCfg = config.programs.dank-material-shell or { };

  shellSwitch = pkgs.writeShellApplication {
    name = "mariano-shell";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd qs pkgs.swaylock pkgs.libnotify ]
      ++ lib.optional (dmsCfg.enable or false) dmsCfg.package;
    text = ''
      # Which shell runs in the niri session: folio or dms.
      #   mariano-shell start            start the chosen one (niri runs this at login)
      #   mariano-shell use folio|dms    switch now and remember it
      #   mariano-shell which            print the choice
      #   mariano-shell ipc TARGET FN …  call Folio's IPC
      #   mariano-shell outputs          point niri at the chosen shell's display layout
      #   mariano-shell fallback         DMS until the next start or use; the choice stays
      config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
      state="$config_home/folio/shell"
      niri="$config_home/niri"
      binds="$niri/shell-binds.kdl"
      marker="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/folio-locked"
      choice() { cat "$state" 2>/dev/null || echo ${cfg.default}; }
      apply_binds() {
        mkdir -p "$niri"
        if [ "$1" = folio ]; then install -m 0644 ${../../dotfiles/niri/folio-binds.kdl} "$binds"; else : > "$binds"; fi
      }
      # Each shell keeps its own display layout file; niri includes the chosen
      # one through shell-outputs.kdl. The first time Folio is chosen it starts
      # from DMS's layout, so the screens stay as they are. Rewritten only when
      # it changes, since every write makes niri reload.
      apply_outputs() {
        mkdir -p "$niri"
        if [ "$1" = folio ]; then
          if [ ! -e "$niri/folio-outputs.kdl" ]; then
            if [ -e "$niri/dms/outputs.kdl" ]; then cp "$niri/dms/outputs.kdl" "$niri/folio-outputs.kdl"; else : > "$niri/folio-outputs.kdl"; fi
            chmod 0644 "$niri/folio-outputs.kdl"
          fi
          line='include optional=true "folio-outputs.kdl"'
        else
          line='include optional=true "dms/outputs.kdl"'
        fi
        want=$(printf '// Written by mariano-shell: the display layout of the shell in use.\n%s\n' "$line")
        if [ "$(cat "$niri/shell-outputs.kdl" 2>/dev/null)" != "$want" ]; then
          printf '%s\n' "$want" > "$niri/shell-outputs.kdl.tmp"
          mv "$niri/shell-outputs.kdl.tmp" "$niri/shell-outputs.kdl"
        fi
      }
      # The lock goes with the shell. niri keeps the session locked when its
      # lock client goes away and lets the next client take that lock over.
      # Folio writes "locked" to $marker while locked and locks again when it
      # starts and finds it; DMS has to be asked. When in doubt it locks: a
      # marker left by a session that ended locked costs one more password.
      folio_locked() { [ "$(cat "$marker" 2>/dev/null)" = locked ]; }
      dms_locked() { [ "$(timeout 3 dms ipc call lock isLocked 2>/dev/null)" = true ]; }
      # DMS answers IPC a moment after its unit is up. If it never takes the
      # lock, swaylock does: locked either way, never a screen with no way in.
      lock_dms() {
        i=0
        while [ "$i" -lt 20 ]; do
          timeout 3 dms ipc call lock lock >/dev/null 2>&1 || true
          sleep 1
          if dms_locked; then : > "$marker"; return 0; fi
          i=$((i + 1))
        done
        echo "mariano-shell: DMS did not take the lock; trying swaylock" >&2
        swaylock -f -e -F && : > "$marker"
      }
      # Run shell $1 instead of the other one, handing over a held lock.
      run_shell() {
        if [ "$1" = folio ]; then
          if systemctl --user is-active --quiet dms.service && dms_locked; then printf 'locked\n' > "$marker"; fi
          systemctl --user stop dms.service || true
          # A crash loop leaves the unit failed (start limit); asking again is a fresh start.
          systemctl --user reset-failed folio-shell.service 2>/dev/null || true
          systemctl --user start folio-shell.service
        else
          held=; if folio_locked; then held=1; fi
          systemctl --user stop folio-shell.service || true
          systemctl --user start dms.service
          if [ -n "$held" ]; then lock_dms; fi
        fi
      }
      case "''${1:-}" in
        start)
          c=$(choice); apply_binds "$c"; apply_outputs "$c"; run_shell "$c" ;;
        use)
          c="''${2:-}"
          if [ "$c" != folio ] && [ "$c" != dms ]; then echo "usage: mariano-shell use folio|dms" >&2; exit 2; fi
          mkdir -p "$(dirname "$state")"; echo "$c" > "$state"
          apply_binds "$c"; apply_outputs "$c"
          run_shell "$c" ;;
        fallback)
          # folio-shell.service gave up (OnFailure=): DMS takes over, with
          # its keys and the lock if one was held, but the display layout and
          # the remembered choice stay Folio's, so the next start or login
          # brings Folio back.
          systemctl --user is-active --quiet graphical-session.target || exit 0
          if systemctl --user is-active --quiet folio-shell.service; then exit 0; fi
          apply_binds dms
          run_shell dms || echo "mariano-shell: the fallback did not finish" >&2   # every step is tried
          notify-send -a "mariano-shell" -u critical "Folio stopped" \
            "It kept failing, so DMS runs for now. mariano-shell start brings Folio back." || true ;;
        which) choice ;;
        outputs) apply_outputs "$(choice)" ;;
        ipc) shift; exec qs ipc -c folio call "$@" ;;
        *) sed -n 's/^ *#   \(mariano-shell \)/\1/p' "$0"; exit 2 ;;
      esac
    '';
  };

  # The units' PATH: the complete session PATH, as dms.service has (launched
  # apps inherit it: /run/wrappers first so a terminal finds the setuid sudo,
  # then ~/.local/bin, the per-user profile, the system profile).
  sessionPath = [ "/run/wrappers" "%h/.local" "/etc/profiles/per-user/mariano" "/run/current-system/sw" ];

  # Every program Folio's QML runs, pinned after the profiles so none goes
  # missing because only another module installed it (brightnessctl came with
  # DMS; inotifywait came with nothing, so Screenshot polled every 2 s), while
  # the profiles' own versions still come first for launched apps. Not here:
  # coreutils, findutils, grep, sed and systemd (NixOS adds them to every
  # unit), sh, getent and ldd (always in the system profile), the optional
  # tools the QML probes for with command -v (khal, codexbar, wlsunset,
  # gammastep) and this repository's own (azure-folio, battery-charge-limit,
  # mariano-capture), which their modules install.
  runtime = [
    qs                                  # About: qs --version
    shellSwitch                         # About: mariano-shell which
    pkgs.brightnessctl                  # Brightness
    pkgs.inotify-tools                  # Screenshot: inotifywait
    pkgs.glib                           # gdbus (Session: lock before sleep; Launcher), gio, gsettings
    pkgs.xdg-utils                      # xdg-open, xdg-mime: Launcher, DefaultApps, Drives, Screenshot
    pkgs.xdg-terminal-exec              # DefaultApps
    pkgs.wl-clipboard                   # Clipboard, Screenshot, About
    pkgs.wl-gammarelay-rs               # NightLight
    pkgs.fd                             # Launcher: file search (find without it)
    pkgs.curl                           # Weather
    pkgs.gawk                           # Screenshot
    pkgs.util-linux                     # Drives: lsblk, findmnt, eject, setsid; About: lscpu; Network: setpriv
    pkgs.pciutils                       # About: lspci
    config.services.udisks2.package     # Drives: udisksctl
  ]
  ++ lib.optional config.programs.niri.enable config.programs.niri.package       # niri msg, niri validate
  ++ lib.optional config.networking.networkmanager.enable config.networking.networkmanager.package  # nmcli
  ++ lib.optionals config.services.pipewire.enable [
    config.services.pipewire.package                                              # pw-dump, pw-metadata, pw-play
    config.services.pipewire.wireplumber.package                                  # wpctl
  ]
  ++ lib.optional config.hardware.bluetooth.enable config.hardware.bluetooth.package  # bluetoothctl
  ++ lib.optional config.services.power-profiles-daemon.enable config.services.power-profiles-daemon.package  # powerprofilesctl
  ++ lib.optional config.services.fprintd.enable config.services.fprintd.package # fprintd-list
  ++ lib.optional config.services.tailscale.enable config.services.tailscale.package;  # tailscale
in
{
  options.mariano.folio = {
    # On for every workstation: niri starts the shell through mariano-shell.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the Folio shell and mariano-shell (the shell switch).";
    };
    default = lib.mkOption {
      type = lib.types.enum [ "folio" "dms" ];
      default = "dms";
      description = "Shell used until mariano-shell use records a choice.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."xdg/quickshell/folio".source = "${folio}/share/folio-shell";

    # The lock screen and polkit dialog run password and fingerprint in two
    # parallel PAM contexts (as DMS does): folio-lock is password-only so a
    # typed password never waits behind the reader; folio-fprint is the reader.
    security.pam.services.folio-lock = {
      allowNullPassword = false;
      fprintAuth = false;
    };
    security.pam.services.folio-fprint = lib.mkIf config.services.fprintd.enable {
      text = ''
        auth required ${pkgs.fprintd}/lib/security/pam_fprintd.so max-tries=3 timeout=30
        account required ${pkgs.pam}/lib/security/pam_unix.so
      '';
    };
    # wl-gammarelay-rs: Night light and inverted colors while Folio is the
    # shell; DMS's own night mode lives in its backend, which Folio does not run.
    # fd: the launcher's file search (it falls back to find without it).
    environment.systemPackages = [ shellSwitch folio pkgs.wl-gammarelay-rs pkgs.fd ];

    # Settings › Storage & drives and the plug-in card read and eject drives
    # through UDisks2 and open them with gvfs (GNOME enables both today; Folio
    # should not depend on that).
    services.udisks2.enable = true;
    services.gvfs.enable = true;

    # A rebuild that changes niri's config must find shell-outputs.kdl already
    # there, or niri would reload with no display layout at all.
    home-manager.users.mariano = { lib, ... }: {
      home.activation.shellOutputs = lib.hm.dag.entryBetween [ "reloadNiri" ] [ "linkGeneration" ] ''
        $DRY_RUN_CMD ${shellSwitch}/bin/mariano-shell outputs
      '';
    };

    # The fallback's last lock client (mariano-shell fallback): swaylock
    # needs a PAM service of its own, which only some hosts define.
    security.pam.services.swaylock = { };

    systemd.user.services.folio-shell = {
      description = "Folio desktop shell";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      conflicts = [ "dms.service" ];
      path = sessionPath ++ runtime;
      # A crash restarts Folio after a second: while the session is locked the
      # screen has no lock client until it is back (it locks again from
      # $XDG_RUNTIME_DIR/folio-locked). Five failed starts in a minute is a
      # crash loop: the unit fails and folio-shell-fallback runs DMS. The
      # default limit (5 in 10 s) never trips when each start lives a few
      # seconds, so a loop would go on for good.
      startLimitIntervalSec = 60;
      startLimitBurst = 5;
      onFailure = [ "folio-shell-fallback.service" ];
      serviceConfig = {
        ExecStart = "${qs}/bin/qs -c folio";
        Restart = "on-failure";
        RestartSec = 1;
        CPUWeight = 150;
      };
    };

    # DMS for the rest of the session, with the lock handed over when one was
    # held; the choice stays Folio (mariano-shell fallback).
    systemd.user.services.folio-shell-fallback = {
      description = "DMS in place of a failed Folio";
      path = sessionPath;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${shellSwitch}/bin/mariano-shell fallback";
        TimeoutStartSec = "5min";
      };
    };
  };
}
