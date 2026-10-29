{ config, lib, pkgs, quickshell, ... }:

# Folio, the desktop shell built in workshop/ (dotfiles/quickshell/folio).
# It runs instead of DMS, never beside it: folio-shell.service conflicts with
# dms.service, and `mariano-shell use folio|dms` switches between them and
# remembers the choice. DMS stays installed as the fallback.
let
  cfg = config.mariano.folio;
  qs = quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  folio = pkgs.callPackage ../../packages/folio-shell.nix { };

  shellSwitch = pkgs.writeShellApplication {
    name = "mariano-shell";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd qs ];
    text = ''
      # Which shell runs in the niri session: folio or dms.
      #   mariano-shell start            start the chosen one (niri runs this at login)
      #   mariano-shell use folio|dms    switch now and remember it
      #   mariano-shell which            print the choice
      #   mariano-shell ipc TARGET FN …  call Folio's IPC
      #   mariano-shell outputs          point niri at the chosen shell's display layout
      config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
      state="$config_home/folio/shell"
      niri="$config_home/niri"
      binds="$niri/shell-binds.kdl"
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
      unit() { if [ "$1" = folio ]; then echo folio-shell.service; else echo dms.service; fi; }
      case "''${1:-}" in
        start)
          c=$(choice); apply_binds "$c"; apply_outputs "$c"; systemctl --user start "$(unit "$c")" ;;
        use)
          c="''${2:-}"
          if [ "$c" != folio ] && [ "$c" != dms ]; then echo "usage: mariano-shell use folio|dms" >&2; exit 2; fi
          mkdir -p "$(dirname "$state")"; echo "$c" > "$state"
          apply_binds "$c"; apply_outputs "$c"
          systemctl --user stop "$(unit "$([ "$c" = folio ] && echo dms || echo folio)")" || true
          systemctl --user start "$(unit "$c")" ;;
        which) choice ;;
        outputs) apply_outputs "$(choice)" ;;
        ipc) shift; exec qs ipc -c folio call "$@" ;;
        *) sed -n 's/^ *#   \(mariano-shell \)/\1/p' "$0"; exit 2 ;;
      esac
    '';
  };
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

    systemd.user.services.folio-shell = {
      description = "Folio desktop shell";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      conflicts = [ "dms.service" ];
      # Same complete PATH as dms.service: launched apps inherit it.
      path = [ "/run/wrappers" "%h/.local" "/etc/profiles/per-user/mariano" "/run/current-system/sw" ];
      serviceConfig = {
        ExecStart = "${qs}/bin/qs -c folio";
        Restart = "on-failure";
        RestartSec = 1;
        CPUWeight = 150;
      };
    };
  };
}
