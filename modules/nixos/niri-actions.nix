# The system actions of the niri desktop: the searchable control palette DMS
# shows (its systemMenu plugin, Mod+Space while DMS is the shell), the theme and
# wallpaper pickers (themeport.kdl), and the built-in display toggle. Restored
# from archive/interstellar-niri's system-actions.nix, which main keeps for
# Update All. Not here: Update All (ackerman's /etc/nixos is not set up for
# it), dictation (voice.nix is GNOME's), Proton VPN and fingerprints (neither
# is on ackerman).
{
  config,
  pkgs,
  ...
}:

let
  niri = config.programs.niri.package;

  displayToggle = pkgs.writeShellApplication {
    name = "mariano-toggle-internal-display";
    runtimeInputs = [
      pkgs.jq
      pkgs.libnotify
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
      util-linux
    ];
    text = ''
      set -eu

      action="''${1:-}"
      if [ "''${MARIANO_ACTION_DRY_RUN:-0}" = 1 ]; then
        case "$action" in
          settings|display-settings|display-toggle-internal|capture-full|capture-region|capture-video|capture-audio-toggle|network-settings|network-speed|bluetooth-toggle|wifi-toggle|power-settings|keep-awake-toggle|notifications-toggle|notifications-1h|notifications-morning|notifications-resume|night-light-toggle|reminders|lock-settings|lock-preview|lock-now|pip-controls|pip-toggle-pin|style-gaps|style-border|theme|wallpaper)
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
          # iwd, not NetworkManager: the radio's soft block is the switch.
          if rfkill list wlan | grep -q 'Soft blocked: no'; then
            rfkill block wlan
            notify-send "Wi-Fi" "Wi-Fi turned off."
          else
            rfkill unblock wlan
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
Focus · Toggle Night Light
Security · Lock now
Security · Preview lock screen
Security · Lock screen & screensaver settings
System · All settings
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
          "Focus · Toggle Night Light"|"Toggle Night Light") action=night-light-toggle ;;
          "Security · Lock now"|"Lock now") action=lock-now ;;
          "Security · Preview lock screen"|"Preview lock screen") action=lock-preview ;;
          "Security · Lock screen & screensaver settings"|"Lock screen & screensaver settings") action=lock-settings ;;
          "System · All settings"|"All settings") action=settings ;;
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
              "Network settings" "Test network speed" "Toggle Wi-Fi" "Toggle Bluetooth" "Back") || return 0
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
              "Stay awake" "Set or manage reminder" "Toggle Night Light" "Back") || return 0
            ;;
          Security)
            choice=$(gum filter --height 9 --header "Security · type to filter · esc/back to categories" \
              "Lock now" "Preview lock screen" "Lock screen & screensaver settings" "Back") || return 0
            ;;
          System)
            choice=$(gum filter --height 9 --header "System · type to filter · esc/back to categories" \
              "All settings" "Back") || return 0
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
  ];
}
