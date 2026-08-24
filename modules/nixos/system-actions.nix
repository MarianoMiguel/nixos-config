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

  actionRunner = pkgs.writeShellApplication {
    name = "mariano-system-action";
    runtimeInputs = with pkgs; [
      bluez
      coreutils
      gnugrep
      libnotify
      networkmanager
      sudo
    ];
    text = ''
      set -eu

      action="''${1:-}"
      if [ "''${MARIANO_ACTION_DRY_RUN:-0}" = 1 ]; then
        case "$action" in
          settings|display-settings|display-toggle-internal|capture-full|capture-region|capture-video|capture-audio-toggle|network-settings|network-speed|bluetooth-toggle|wifi-toggle|power-settings|keep-awake-toggle|notifications-toggle|notifications-1h|notifications-morning|notifications-resume|night-light-toggle|dictate|reminders|lock-settings|lock-preview|lock-now|pip-controls|pip-toggle-pin|scratchpad-toggle|scratchpad-send|theme|wallpaper|proton-vpn|fingerprint-user|fingerprint-admin|update)
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
        scratchpad-toggle)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Scratchpad" "Scratchpads are available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/niri-scratchpad toggle
          ;;
        scratchpad-send)
          if [ "''${XDG_CURRENT_DESKTOP:-}" != niri ]; then
            notify-send "Scratchpad" "Scratchpads are available in the Niri session."
            exit 1
          fi
          exec /run/current-system/sw/bin/niri-scratchpad send
          ;;
        theme)
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Choose Theme" -e \
            /run/current-system/sw/bin/themeport pick --hold
          ;;
        wallpaper)
          if [ "''${XDG_CURRENT_DESKTOP:-}" = niri ]; then
            exec /run/current-system/sw/bin/dms ipc call dash open wallpaper
          else
            exec /run/current-system/sw/bin/gnome-control-center background
          fi
          ;;
        proton-vpn)
          exec /run/current-system/sw/bin/protonvpn-app
          ;;
        fingerprint-user)
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Fingerprint for Login and Unlock" -e \
            ${pkgs.fprintd}/bin/fprintd-enroll mariano
          ;;
        fingerprint-admin)
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="Fingerprint for Sudo" -e \
            ${pkgs.sudo}/bin/sudo ${pkgs.fprintd}/bin/fprintd-enroll root
          ;;
        update)
          exec /run/current-system/sw/bin/ghostty --class=system.actions --title="NixOS Update" -e \
            ${pkgs.sudo}/bin/sudo ${systemUpdate}/bin/mariano-system-update
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

      print_catalog() {
        cat <<'CATALOG'
Appearance · Choose theme
Appearance · Choose wallpaper
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
Windows · Toggle scratchpad for this display
Windows · Move focused window to scratchpad
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
${lib.optionalString fingerprintEnabled ''Security · Fingerprint for login and unlock
Security · Fingerprint for sudo
''}System · All settings
System · Update NixOS packages
CATALOG
      }

      set_action() {
        case "$1" in
          "Appearance · Choose theme"|"Choose theme") action=theme ;;
          "Appearance · Choose wallpaper"|"Choose wallpaper") action=wallpaper ;;
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
          "Windows · Toggle scratchpad for this display"|"Toggle scratchpad for this display") action=scratchpad-toggle ;;
          "Windows · Move focused window to scratchpad"|"Move focused window to scratchpad") action=scratchpad-send ;;
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
${lib.optionalString fingerprintEnabled ''          "Security · Fingerprint for login and unlock"|"Fingerprint for login and unlock") action=fingerprint-user ;;
          "Security · Fingerprint for sudo"|"Fingerprint for sudo") action=fingerprint-admin ;;
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
              "Choose theme" "Choose wallpaper" "Back") || return 0
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
              "Picture-in-Picture controls" "Toggle pin focused window" \
              "Toggle scratchpad for this display" "Move focused window to scratchpad" "Back") || return 0
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
              ${lib.optionalString fingerprintEnabled ''"Fingerprint for login and unlock" "Fingerprint for sudo"''} "Back") || return 0
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

  actionSpecs = [
    {
      id = "settings";
      name = "System · Settings";
      comment = "Open the unified DMS settings";
      icon = "preferences-system";
    }
    {
      id = "display-settings";
      name = "System · Displays · Settings";
      comment = "Configure displays in DMS";
      icon = "video-display";
    }
    {
      id = "display-toggle-internal";
      name = "System · Displays · Toggle laptop display";
      comment = "Safely turn the built-in display on or off";
      icon = "video-display";
    }
    {
      id = "capture-full";
      name = "System · Capture · Full screenshot";
      comment = "Capture all displays and copy the image to the clipboard";
      icon = "camera-photo";
    }
    {
      id = "capture-region";
      name = "System · Capture · Region screenshot";
      comment = "Select a region, save it and copy the image to the clipboard";
      icon = "camera-photo";
    }
    {
      id = "capture-video";
      name = "System · Capture · Start or stop region recording";
      comment = "Select a region to record, or finish the active recording";
      icon = "media-record";
    }
    {
      id = "capture-audio-toggle";
      name = "System · Capture · Toggle system audio in recordings";
      comment = "Remember whether new screen recordings include desktop audio";
      icon = "audio-volume-high";
    }
    {
      id = "network-settings";
      name = "System · Connections · Settings";
      comment = "Configure Wi-Fi, Bluetooth and connections in DMS";
      icon = "network-wireless";
    }
    {
      id = "network-speed";
      name = "System · Connections · Test network speed";
      comment = "Open the on-demand network speed panel without result sharing";
      icon = "network-transmit-receive";
    }
    {
      id = "bluetooth-toggle";
      name = "System · Connections · Toggle Bluetooth";
      comment = "Turn Bluetooth on or off";
      icon = "bluetooth-active";
    }
    {
      id = "wifi-toggle";
      name = "System · Connections · Toggle Wi-Fi";
      comment = "Turn Wi-Fi on or off";
      icon = "network-wireless";
    }
    {
      id = "power-settings";
      name = "System · Power · Power & Sleep settings";
      comment = "Configure locking, display power and sleep in DMS";
      icon = "preferences-system-power-management";
    }
    {
      id = "keep-awake-toggle";
      name = "System · Focus · Stay awake";
      comment = "Temporarily prevent automatic display power-off, locking and sleep";
      icon = "caffeine-cup-full";
    }
    {
      id = "notifications-toggle";
      name = "System · Focus · Silence notifications";
      comment = "Toggle DMS Do Not Disturb";
      icon = "notifications-disabled";
    }
    {
      id = "notifications-1h";
      name = "System · Focus · Silence notifications for 1 hour";
      comment = "Enable Do Not Disturb for one hour";
      icon = "notifications-disabled";
    }
    {
      id = "notifications-morning";
      name = "System · Focus · Silence notifications until tomorrow morning";
      comment = "Enable Do Not Disturb until 08:00 tomorrow";
      icon = "notifications-disabled";
    }
    {
      id = "notifications-resume";
      name = "System · Focus · Resume notifications";
      comment = "Disable Do Not Disturb";
      icon = "preferences-system-notifications";
    }
    {
      id = "reminders";
      name = "System · Focus · Set or manage reminder";
      comment = "Schedule a private local desktop reminder";
      icon = "appointment-soon";
    }
    {
      id = "dictate";
      name = "System · Focus · Dictate";
      comment = "Start or stop local speech-to-text dictation";
      icon = "audio-input-microphone";
    }
    {
      id = "night-light-toggle";
      name = "System · Focus · Toggle Night Light";
      comment = "Toggle the DMS warm display color mode";
      icon = "weather-clear-night";
    }
    {
      id = "lock-now";
      name = "System · Security · Lock now";
      comment = "Lock the current session immediately";
      icon = "system-lock-screen";
    }
    {
      id = "lock-preview";
      name = "System · Security · Preview lock screen";
      comment = "Preview the minimal lock screen without locking";
      icon = "system-lock-screen";
    }
    {
      id = "lock-settings";
      name = "System · Security · Lock screen & screensaver settings";
      comment = "Configure lock appearance, authentication and the optional video screensaver";
      icon = "preferences-desktop-screensaver";
    }
    {
      id = "pip-controls";
      name = "System · Windows · Picture-in-Picture controls";
      comment = "Control sticky Picture-in-Picture windows in Niri";
      icon = "video-display";
    }
    {
      id = "pip-toggle-pin";
      name = "System · Windows · Toggle pin focused window";
      comment = "Pin or unpin the focused Niri window across workspaces";
      icon = "window-pin";
    }
    {
      id = "scratchpad-toggle";
      name = "System · Windows · Toggle scratchpad for this display";
      comment = "Summon or hide this display's Niri scratchpad";
      icon = "window-restore";
    }
    {
      id = "scratchpad-send";
      name = "System · Windows · Move focused window to scratchpad";
      comment = "Store the focused window in this display's Niri scratchpad";
      icon = "window-minimize";
    }
    {
      id = "theme";
      name = "System · Appearance · Choose theme";
      comment = "Choose an immutable, reviewed system theme";
      icon = "preferences-desktop-theme";
    }
    {
      id = "wallpaper";
      name = "System · Appearance · Choose wallpaper";
      comment = "Open the DMS wallpaper browser";
      icon = "preferences-desktop-wallpaper";
    }
    {
      id = "proton-vpn";
      name = "System · Connections · Proton VPN";
      comment = "Open Proton VPN";
      icon = "proton-vpn";
    }
    {
      id = "update";
      name = "System · Update NixOS packages";
      comment = "Update reviewed stable inputs and activate the new generation";
      icon = "system-software-update";
    }
  ] ++ lib.optionals fingerprintEnabled [
    {
      id = "fingerprint-user";
      name = "System · Security · Fingerprint for login and unlock";
      comment = "Enroll a fingerprint for Mariano";
      icon = "fingerprint-gui";
    }
    {
      id = "fingerprint-admin";
      name = "System · Security · Fingerprint for sudo";
      comment = "Enroll a separate fingerprint for the root administrator account";
      icon = "fingerprint-gui";
    }
  ];

  desktopItems = map (action: pkgs.makeDesktopItem {
    name = "mariano-system-${action.id}";
    desktopName = action.name;
    inherit (action) comment icon;
    exec = "${actionRunner}/bin/mariano-system-action ${action.id}";
    categories = [ "Settings" ];
    keywords = [
      "System"
      "Settings"
      action.id
    ];
    terminal = false;
  }) actionSpecs;

  systemMenuDesktop = pkgs.makeDesktopItem {
    name = "mariano-system-actions";
    desktopName = "System Actions";
    comment = "Search system settings, toggles and maintenance";
    exec = ''${pkgs.ghostty}/bin/ghostty --class=system.actions --title="System Actions" -e ${systemMenu}/bin/mariano-system-menu'';
    icon = "preferences-system";
    categories = [ "Settings" ];
    keywords = [
      "System"
      "Actions"
      "Settings"
      "Toggle"
    ];
    terminal = false;
  };
in
{
  environment.systemPackages = [
    actionRunner
    displayToggle
    systemMenu
    systemMenuDesktop
    systemUpdate
  ] ++ desktopItems;
}
