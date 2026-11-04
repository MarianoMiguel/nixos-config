{
  config,
  lib,
  pkgs,
  ...
}:

let
  fingerprintEnabled = config.services.fprintd.enable;

  # Update the inputs, commit the new flake.lock in the administrator's
  # checkout (/etc/nixos), build that commit from git and switch to it. Only
  # committed code is built: a dirty checkout or a .nix file git does not
  # track is refused. The body is scripts/system-update.sh, which
  # tests/system-update.sh exercises against a scratch checkout.
  mkSystemUpdate =
    {
      name,
      updateDescription,
      commitSummary,
      updateInputs ? [ ],
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        findutils
        gawk
        git
        glibc
        gnugrep
        gnused
        nix
        nixos-rebuild
        util-linux
      ];
      text = ''
        host=${lib.escapeShellArg config.networking.hostName}
        update_description=${lib.escapeShellArg updateDescription}
        commit_summary=${lib.escapeShellArg commitSummary}
        update_inputs=(${lib.escapeShellArgs updateInputs})
        config_link=/etc/nixos
        state_dir=/var/lib/mariano-system-update
        current_system=/run/current-system
        system_profile=/nix/var/nix/profiles/system

      ''
      + builtins.readFile ../../scripts/system-update.sh;
    };

  systemUpdate = mkSystemUpdate {
    name = "mariano-system-update";
    updateDescription = "Updating reviewed stable inputs (nixpkgs, Home Manager and Disko)...";
    commitSummary = "flake.lock: update nixpkgs, Home Manager and Disko";
    updateInputs = [
      "nixpkgs"
      "home-manager"
      "disko"
    ];
  };

  systemUpdateAll = mkSystemUpdate {
    name = "mariano-system-update-all";
    updateDescription = "Updating all movable flake inputs, including Codex Desktop...";
    commitSummary = "flake.lock: update all inputs";
  };

  # Enroll, list or delete fingerprints, for login and unlock (Mariano) or
  # for sudo (root, through NixOS's setuid wrapper). Run it in a terminal.
  fingerprintManager = pkgs.writeShellApplication {
    name = "mariano-fingerprint-manager";
    runtimeInputs = with pkgs; [ fprintd gum ];
    text = ''
      set -eu

      pause() {
        printf '\nPress Enter to continue.'
        read -r _ || true
      }

      manage_account() {
        account=$1
        label=$2
        elevated=$3

        run_fprint() {
          if [ "$elevated" = 1 ]; then
            /run/wrappers/bin/sudo "$@"
          else
            "$@"
          fi
        }

        while choice=$(gum choose --header "$label" \
          "Enroll a fingerprint" "List enrolled fingerprints" "Delete all fingerprints" "Back"); do
          case "$choice" in
            "Enroll a fingerprint")
              finger=$(gum choose --header "Choose the finger to enroll" \
                right-index-finger right-middle-finger right-ring-finger right-little-finger right-thumb \
                left-index-finger left-middle-finger left-ring-finger left-little-finger left-thumb) || continue
              run_fprint ${pkgs.fprintd}/bin/fprintd-enroll -f "$finger" "$account" || true
              pause
              ;;
            "List enrolled fingerprints")
              run_fprint ${pkgs.fprintd}/bin/fprintd-list "$account" || true
              pause
              ;;
            "Delete all fingerprints")
              if gum confirm "Delete every fingerprint enrolled for $account?"; then
                run_fprint ${pkgs.fprintd}/bin/fprintd-delete "$account" || true
                pause
              fi
              ;;
            Back)
              return 0
              ;;
          esac
        done
      }

      while account_choice=$(gum choose --header "Fingerprint setup" \
        "Login and unlock (Mariano)" "Administrator authentication (sudo)" "Close"); do
        case "$account_choice" in
          "Login and unlock (Mariano)")
            manage_account "''${USER:?USER is required}" "Login and unlock fingerprints · no sudo required" 0
            ;;
          "Administrator authentication (sudo)")
            manage_account root "Administrator fingerprints · use a different finger" 1
            ;;
          Close)
            exit 0
            ;;
        esac
      done
    '';
  };

  updateNudge = pkgs.writeShellApplication {
    name = "mariano-update-nudge";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      libnotify
    ];
    text = ''
      set -eu

      lock=/etc/nixos/flake.lock
      [ -r "$lock" ] || exit 0
      locked=$(jq -r '.nodes[.nodes[.root].inputs.nixpkgs].locked.lastModified // empty' "$lock")
      [ -n "$locked" ] || exit 0
      age_days=$(( ( $(date +%s) - locked ) / 86400 ))
      [ "$age_days" -ge 14 ] || exit 0
      notify-send --app-name="NixOS" --icon=system-software-update \
        "NixOS inputs are $age_days days old" \
        "Run sudo mariano-system-update-all in a terminal when convenient."
    '';
  };
in
{
  # Nudge, never auto-update: twice a week, if the locked nixpkgs is older
  # than two weeks, one notification points at the all-packages update.
  systemd.user.services.nixos-update-nudge = {
    description = "Remind about stale NixOS inputs";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateNudge}/bin/mariano-update-nudge";
    };
  };
  systemd.user.timers.nixos-update-nudge = {
    description = "Check the age of the locked NixOS inputs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon,Thu 10:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };

  environment.systemPackages = [
    systemUpdate
    systemUpdateAll
  ] ++ lib.optionals fingerprintEnabled [ fingerprintManager ];
}
