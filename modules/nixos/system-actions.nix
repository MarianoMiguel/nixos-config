{
  config,
  lib,
  pkgs,
  ...
}:

let
  fingerprintEnabled = config.services.fprintd.enable;

  systemUpdate = pkgs.writeShellApplication {
    name = "mariano-system-update";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      nix
      nixos-rebuild
    ];
    text = ''
      set -eu

      config_dir=/etc/nixos
      state_dir=/var/lib/mariano-system-update
      lock_file="$config_dir/flake.lock"
      backup="$state_dir/flake.lock.previous"

      if [ "$(id -u)" -ne 0 ]; then
        echo "This fixed updater must run as root." >&2
        exit 1
      fi
      if [ ! -d "$config_dir" ] || [ -L "$config_dir" ] || [ ! -f "$lock_file" ]; then
        echo "/etc/nixos must be a real configuration directory with a flake.lock." >&2
        exit 1
      fi

      unsafe=$(find "$config_dir" -xdev \( -type l -o ! -user root -o -perm /022 \) -print -quit)
      if [ -n "$unsafe" ]; then
        echo "Refusing to update: /etc/nixos contains an unsafe path: $unsafe" >&2
        exit 1
      fi

      install -d -m 0700 "$state_dir"
      install -m 0600 "$lock_file" "$backup"
      restore_lock() {
        install -m 0644 "$backup" "$lock_file"
      }
      trap restore_lock INT TERM HUP

      echo "Updating reviewed stable inputs (nixpkgs, Home Manager and Disko)..."
      if ! nix flake update --flake "path:$config_dir" nixpkgs home-manager disko; then
        restore_lock
        echo "Input update failed; the previous lock file was restored." >&2
        exit 1
      fi

      echo "Building and activating ${config.networking.hostName}..."
      if ! nixos-rebuild switch --flake "path:$config_dir#${config.networking.hostName}"; then
        restore_lock
        echo "Activation failed; the previous lock file was restored and the previous boot generation remains available." >&2
        exit 1
      fi

      trap - INT TERM HUP
      echo "System update complete. The previous lock file is in $backup."
    '';
  };

  displayToggle = pkgs.writeShellApplication {
    name = "mariano-toggle-internal-display";
    runtimeInputs = with pkgs; [
      jq
      libnotify
      niri
    ];
    text = ''
      set -eu

      notify() {
        if [ "''${MARIANO_ACTION_DRY_RUN:-0}" = 1 ]; then
          printf 'notification: %s\n' "$1"
        else
          notify-send "Displays" "$1"
        fi
      }

      if [ -n "''${MARIANO_NIRI_OUTPUTS_JSON:-}" ]; then
        outputs=$MARIANO_NIRI_OUTPUTS_JSON
      else
        outputs=$(niri msg --json outputs)
      fi

      internal=$(printf '%s' "$outputs" | jq -r '
        to_entries
        | (map(select(.key | startswith("eDP-")))[0].key
          // map(select(
            .value.make == "Lenovo Group Limited"
            and (.value.model // "" | startswith("B140UAN"))
          ))[0].key
          // empty)
      ')
      if [ -z "$internal" ]; then
        notify "No built-in laptop display was found."
        exit 1
      fi

      enabled=$(printf '%s' "$outputs" | jq -r --arg output "$internal" '.[$output].current_mode != null')
      if [ "$enabled" = "true" ]; then
        other_enabled=$(printf '%s' "$outputs" | jq -r --arg output "$internal" '
          [to_entries[] | select(.key != $output and .value.current_mode != null)] | length
        ')
        if [ "$other_enabled" -eq 0 ]; then
          notify "Connect and enable another display before turning off $internal."
          exit 1
        fi
        desired=off
      else
        desired=on
      fi

      if [ "''${MARIANO_ACTION_DRY_RUN:-0}" = 1 ]; then
        printf 'niri msg output %s %s\n' "$internal" "$desired"
        exit 0
      fi

      niri msg output "$internal" "$desired"
      notify "Built-in display $internal turned $desired."
    '';
  };

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

  dmsPicker = pkgs.writeShellApplication {
    name = "mariano-dms-picker";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu

      case "''${1:-}" in
        sys) query='sys ' ;;
        theme) query='theme ' ;;
        wall) query='wall ' ;;
        *)
          echo "usage: mariano-dms-picker sys|theme|wall" >&2
          exit 2
          ;;
      esac

      if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
        echo "The DMS picker is available only in the Niri session." >&2
        exit 1
      fi

      # Selecting Theme or Wallpaper from the system palette first closes the
      # current DMS launcher. A short deferred reopen avoids that close racing
      # the next visual picker.
      delay="''${MARIANO_DMS_PICKER_DELAY:-0}"
      [ "$delay" = 0 ] || sleep "$delay"
      exec /run/current-system/sw/bin/dms ipc call launcher openQuery "$query"
    '';
  };

  actionRunner = pkgs.writeShellApplication {
    name = "mariano-system-action";
    runtimeInputs = with pkgs; [
      bluez
      coreutils
      gnugrep
      libnotify
      networkmanager
    ];
    text = ''
      set -eu

      action="''${1:-}"
      if [ "''${MARIANO_ACTION_DRY_RUN:-0}" = 1 ]; then
        case "$action" in
          settings|display-settings|display-toggle-internal|capture-full|capture-region|capture-video|capture-audio-toggle|network-settings|network-speed|bluetooth-toggle|wifi-toggle|power-settings|keep-awake-toggle|notifications-toggle|notifications-1h|notifications-morning|notifications-resume|night-light-toggle|dictate|reminders|lock-settings|lock-preview|lock-now|pip-controls|pip-toggle-pin|style-gaps|style-border|theme|wallpaper|proton-vpn|fingerprint|update)
            printf '%s\n' "$action"
            exit 0
            ;;
        esac
      fi

      case "$action" in
        settings)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call settings focusOrToggle
          else
            exec /run/current-system/sw/bin/gnome-control-center
          fi
          ;;
        display-settings)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call settings focusOrToggleWith displays
          else
            exec /run/current-system/sw/bin/gnome-control-center display
          fi
          ;;
        display-toggle-internal)
          exec ${displayToggle}/bin/mariano-toggle-internal-display
          ;;
        capture-full)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Capture" "This capture workflow is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/mariano-capture screenshot-full
          ;;
        capture-region)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Capture" "This capture workflow is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/mariano-capture screenshot-region
          ;;
        capture-video)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Capture" "This capture workflow is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/mariano-capture video-toggle
          ;;
        capture-audio-toggle)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Capture" "This capture workflow is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/mariano-capture audio-toggle
          ;;
        network-settings)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call settings focusOrToggleWith network
          else
            exec /run/current-system/sw/bin/gnome-control-center network
          fi
          ;;
        network-speed)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Network speed" "The integrated speed test is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call widget toggle networkSpeed
          ;;
        bluetooth-toggle)
          if bluetoothctl show | grep -q 'Powered: yes'; then
            bluetoothctl power off
            notify-send "Bluetooth" "Bluetooth turned off."
          else
            bluetoothctl power on
            notify-send "Bluetooth" "Bluetooth turned on."
          fi
          ;;
        wifi-toggle)
          if [ "$(nmcli radio wifi)" = enabled ]; then
            nmcli radio wifi off
            notify-send "Wi-Fi" "Wi-Fi turned off."
          else
            nmcli radio wifi on
            notify-send "Wi-Fi" "Wi-Fi turned on."
          fi
          ;;
        power-settings)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call settings focusOrToggleWith power_sleep
          else
            exec /run/current-system/sw/bin/gnome-control-center power
          fi
          ;;
        keep-awake-toggle)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Keep Awake" "Use the Power settings for this desktop session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call inhibit toggle
          ;;
        notifications-toggle)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Notifications" "Notification silence is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call notifications toggleDoNotDisturb
          ;;
        notifications-1h)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Notifications" "Notification silence is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call notifications enableDoNotDisturbFor 60
          ;;
        notifications-morning)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Notifications" "Notification silence is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call notifications enableDoNotDisturbUntilTomorrowMorning
          ;;
        notifications-resume)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Notifications" "Notification silence is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call notifications disableDoNotDisturb
          ;;
        night-light-toggle)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Night Light" "Night Light is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call night toggle
          ;;
        dictate)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Dictation" "Dictation is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/voiceagent dictate
          ;;
        reminders)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call widget toggle focus
          else
            exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Reminders" -e \
              /run/current-system/sw/bin/mariano-reminder interactive
          fi
          ;;
        lock-settings)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call settings focusOrToggleWith lock_screen
          else
            exec /run/current-system/sw/bin/gnome-control-center privacy
          fi
          ;;
        lock-preview)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Lock Screen" "Lock screen preview is available in the Niri session."
            exit 1
          fi
          /run/current-system/sw/bin/dms ipc call lock demo
          ;;
        lock-now)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            /run/current-system/sw/bin/dms ipc call lock lock
          else
            /run/current-system/sw/bin/loginctl lock-session
          fi
          ;;
        pip-controls)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Picture-in-Picture" "These controls are available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Picture-in-Picture Controls" -e \
            /run/current-system/sw/bin/niripip menu
          ;;
        pip-toggle-pin)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Pinned window" "Window pinning is available in the Niri session."
            exit 1
          fi
          if result=$(/run/current-system/sw/bin/niripip toggle 2>&1); then
            notify-send "Pinned window" "$result"
          else
            notify-send "Pinned window" "$result"
            exit 1
          fi
          ;;
        style-gaps)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Window gaps" "Window gap toggling is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/niri-style-toggle gaps
          ;;
        style-border)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Window borders" "Window border toggling is available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/niri-style-toggle border
          ;;
        theme)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            export MARIANO_DMS_PICKER_DELAY=0.15
            exec ${dmsPicker}/bin/mariano-dms-picker theme
          else
            exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Choose Theme" -e \
              /run/current-system/sw/bin/themeport pick --hold
          fi
          ;;
        wallpaper)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            export MARIANO_DMS_PICKER_DELAY=0.15
            exec ${dmsPicker}/bin/mariano-dms-picker wall
          else
            exec /run/current-system/sw/bin/gnome-control-center background
          fi
          ;;
        proton-vpn)
          exec /run/current-system/sw/bin/protonvpn-app
          ;;
        fingerprint)
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Fingerprint Setup" -e \
            ${fingerprintManager}/bin/mariano-fingerprint-manager
          ;;
        update)
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="NixOS Update" -e \
            /run/wrappers/bin/sudo ${systemUpdate}/bin/mariano-system-update
          ;;
        *)
          echo "Unknown system action: $action" >&2
          exit 2
          ;;
      esac
    '';
  };

  systemMenu = pkgs.writeShellApplication {
    name = "mariano-system-menu";
    runtimeInputs = with pkgs; [ gum ];
    text = ''
      set -eu

      if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ] && [ "''${1:-}" != --terminal ]; then
        exec ${dmsPicker}/bin/mariano-dms-picker sys
      fi
      if [ "''${1:-}" = --terminal ]; then
        shift
      fi

      print_catalog() {
        cat <<'CATALOG'
Appearance · Choose theme
Appearance · Choose wallpaper
Appearance · Toggle window gaps
Appearance · Toggle window borders
Connections · Network settings
Connections · Test network speed
Connections · Toggle Wi-Fi
Connections · Toggle Bluetooth
Connections · Proton VPN
Displays · Display settings
Displays · Toggle laptop display
Capture · Full screenshot
Capture · Region screenshot
Capture · Start or stop region recording
Capture · Toggle system audio in recordings
Windows · Picture-in-Picture controls
Windows · Toggle pin focused window
Power · Power & Sleep settings
Focus · Silence notifications
Focus · Silence notifications for 1 hour
Focus · Silence notifications until tomorrow morning
Focus · Resume notifications
Focus · Stay awake
Focus · Set or manage reminder
Focus · Dictate
Focus · Toggle Night Light
Security · Lock now
Security · Preview lock screen
Security · Lock screen & screensaver settings
${lib.optionalString fingerprintEnabled ''Security · Set up fingerprints
''}System · All settings
System · Update NixOS packages
CATALOG
      }

      set_action() {
        case "$1" in
          "Appearance · Choose theme"|"Choose theme") action=theme ;;
          "Appearance · Choose wallpaper"|"Choose wallpaper") action=wallpaper ;;
          "Appearance · Toggle window gaps"|"Toggle window gaps") action=style-gaps ;;
          "Appearance · Toggle window borders"|"Toggle window borders") action=style-border ;;
          "Connections · Network settings"|"Network settings") action=network-settings ;;
          "Connections · Test network speed"|"Test network speed") action=network-speed ;;
          "Connections · Toggle Wi-Fi"|"Toggle Wi-Fi") action=wifi-toggle ;;
          "Connections · Toggle Bluetooth"|"Toggle Bluetooth") action=bluetooth-toggle ;;
          "Connections · Proton VPN"|"Proton VPN") action=proton-vpn ;;
          "Displays · Display settings"|"Display settings") action=display-settings ;;
          "Displays · Toggle laptop display"|"Toggle laptop display") action=display-toggle-internal ;;
          "Capture · Full screenshot"|"Full screenshot") action=capture-full ;;
          "Capture · Region screenshot"|"Region screenshot") action=capture-region ;;
          "Capture · Start or stop region recording"|"Start or stop region recording") action=capture-video ;;
          "Capture · Toggle system audio in recordings"|"Toggle system audio in recordings") action=capture-audio-toggle ;;
          "Windows · Picture-in-Picture controls"|"Picture-in-Picture controls") action=pip-controls ;;
          "Windows · Toggle pin focused window"|"Toggle pin focused window") action=pip-toggle-pin ;;
          "Power · Power & Sleep settings"|"Power & Sleep settings") action=power-settings ;;
          "Focus · Silence notifications"|"Silence notifications") action=notifications-toggle ;;
          "Focus · Silence notifications for 1 hour"|"Silence notifications for 1 hour") action=notifications-1h ;;
          "Focus · Silence notifications until tomorrow morning"|"Silence notifications until tomorrow morning") action=notifications-morning ;;
          "Focus · Resume notifications"|"Resume notifications") action=notifications-resume ;;
          "Focus · Stay awake"|"Stay awake") action=keep-awake-toggle ;;
          "Focus · Set or manage reminder"|"Set or manage reminder") action=reminders ;;
          "Focus · Dictate"|"Dictate") action=dictate ;;
          "Focus · Toggle Night Light"|"Toggle Night Light") action=night-light-toggle ;;
          "Security · Lock now"|"Lock now") action=lock-now ;;
          "Security · Preview lock screen"|"Preview lock screen") action=lock-preview ;;
          "Security · Lock screen & screensaver settings"|"Lock screen & screensaver settings") action=lock-settings ;;
${lib.optionalString fingerprintEnabled ''          "Security · Set up fingerprints"|"Set up fingerprints") action=fingerprint ;;
''}          "System · All settings"|"All settings") action=settings ;;
          "System · Update NixOS packages"|"Update NixOS packages") action=update ;;
          *)
            echo "Unknown system action: $1" >&2
            exit 2
            ;;
        esac
      }

      show_category() {
        category=$1
        case "$category" in
          Appearance)
            choice=$(gum filter --height 9 --header "Appearance · type to filter · esc/back to categories" \
              "Choose theme" "Choose wallpaper" "Toggle window gaps" "Toggle window borders" "Back") || return 0
            ;;
          Connections)
            choice=$(gum filter --height 9 --header "Connections · type to filter · esc/back to categories" \
              "Network settings" "Test network speed" "Toggle Wi-Fi" "Toggle Bluetooth" "Proton VPN" "Back") || return 0
            ;;
          Displays)
            choice=$(gum filter --height 9 --header "Displays · type to filter · esc/back to categories" \
              "Display settings" "Toggle laptop display" "Back") || return 0
            ;;
          Capture)
            choice=$(gum filter --height 9 --header "Capture · type to filter · esc/back to categories" \
              "Full screenshot" "Region screenshot" "Start or stop region recording" \
              "Toggle system audio in recordings" "Back") || return 0
            ;;
          Windows)
            choice=$(gum filter --height 9 --header "Windows · type to filter · esc/back to categories" \
              "Picture-in-Picture controls" "Toggle pin focused window" "Back") || return 0
            ;;
          Power)
            choice=$(gum filter --height 9 --header "Power · type to filter · esc/back to categories" \
              "Power & Sleep settings" "Back") || return 0
            ;;
          Focus)
            choice=$(gum filter --height 12 --header "Focus · type to filter · esc/back to categories" \
              "Silence notifications" "Silence notifications for 1 hour" \
              "Silence notifications until tomorrow morning" "Resume notifications" \
              "Stay awake" "Set or manage reminder" "Dictate" "Toggle Night Light" "Back") || return 0
            ;;
          Security)
            choice=$(gum filter --height 9 --header "Security · type to filter · esc/back to categories" \
              "Lock now" "Preview lock screen" "Lock screen & screensaver settings" \
              ${lib.optionalString fingerprintEnabled ''"Set up fingerprints"''} "Back") || return 0
            ;;
          System)
            choice=$(gum filter --height 9 --header "System · type to filter · esc/back to categories" \
              "All settings" "Update NixOS packages" "Back") || return 0
            ;;
          *)
            echo "Unknown system action category: $category" >&2
            exit 2
            ;;
        esac

        [ "$choice" = Back ] && return 0
        set_action "$choice"
        exec ${actionRunner}/bin/mariano-system-action "$action"
      }

      if [ "''${1:-}" = --print-catalog ]; then
        print_catalog
        exit 0
      fi

      if [ "''${1:-}" = --category ]; then
        show_category "''${2:-}"
        exit 0
      fi

      if [ "''${1:-}" = --categories ]; then
        while category=$(gum filter --height 9 --header "System Actions · type to filter · esc to close" \
          "Appearance" "Connections" "Displays" "Capture" "Windows" "Focus" "Power" "Security" "System"); do
          show_category "$category"
        done
        exit 0
      fi

      choice=$(print_catalog | gum filter --height 16 \
        --header "System Actions · type to filter · esc to close") || exit 0
      set_action "$choice"
      exec ${actionRunner}/bin/mariano-system-action "$action"
    '';
  };

in
{
  environment.systemPackages = [
    actionRunner
    dmsPicker
    displayToggle
    systemMenu
    systemUpdate
  ] ++ lib.optionals fingerprintEnabled [ fingerprintManager ];
}
