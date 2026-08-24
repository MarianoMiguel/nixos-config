{ config, lib, pkgs, ... }:

let
  home = "/home/mariano";
  dotfiles = ../../dotfiles;
  mutableState = "${home}/.local/state/nixos-config/dotfiles";
  fingerprintEnabled = config.services.fprintd.enable;
  # Keep one immutable wallpaper catalog for Themeport, the DMS settings page,
  # DankDash and the visual picker. A flat directory is intentional: DMS shows
  # siblings of the active wallpaper, so any selection keeps the whole catalog
  # visible.
  omarchyThemes = pkgs.fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "5d3299fb9426ae927b9fc7ef16c94bd334a90f01";
    hash = "sha256-smjQlpZd7mzMrxV6PQFjXRwVm0s8xybBthcIrvrTYUA=";
  };
  wallpaperLibrary = pkgs.runCommandLocal "mariano-wallpaper-library" { } ''
    mkdir -p "$out"
    cp -a ${../../assets/wallpapers}/. "$out/"
    chmod u+w "$out"

    find ${omarchyThemes}/themes -mindepth 3 -maxdepth 3 \
      -path '*/backgrounds/*' -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
      -print | while IFS= read -r source; do
        theme_dir=$(dirname "$(dirname "$source")")
        theme=$(basename "$theme_dir")
        filename=$(basename "$source")
        ln -s "$source" "$out/$theme--$filename"
      done
  '';
  mutableDotfiles = [
    "dms/plugin-settings.json"
    "dms/session.json"
    "dms/settings.json"
    "dms/theme.json"
    "dms/themes/dms-ayu/theme.json"
    "niri/dms/alttab.kdl"
    "niri/dms/binds.kdl"
    "niri/dms/colors.kdl"
    "niri/dms/cursor.kdl"
    "niri/dms/layout.kdl"
    "niri/dms/outputs.kdl"
    "niri/dms/windowrules.kdl"
    "niri/dms/wpblur.kdl"
    "niri/toggles/gaps.kdl"
    "niri/toggles/border.kdl"
    "niri/toggles/radius.kdl"
    "nvim/lazy-lock.json"
    "nvim/lua/plugins/dankcolors.lua"
    "themeport"
    "vscode/User/settings.json"
  ];
  # These files are copied by a Home Manager activation script rather than
  # linked directly into the profile. Put their contents in a dedicated store
  # output so prebuilt/offline installations retain them in the system closure;
  # referring to the original flake source path here left fresh installs with
  # a dangling activation-time path.
  mutableDotfileSeed = pkgs.runCommandLocal "mariano-mutable-dotfile-seed" { } ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (path: ''
      mkdir -p "$out/${builtins.dirOf path}"
      cp -a ${dotfiles}/${path} "$out/${path}"
    '') mutableDotfiles}
  '';
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-nixos";

    users.mariano =
      { config, lib, ... }:
      let
        mutableDotfile = path: config.lib.file.mkOutOfStoreSymlink "${mutableState}/${path}";
        nvimConfig = pkgs.runCommand "nvim-config" { } ''
          mkdir -p "$out"
          cp -a ${dotfiles}/nvim/. "$out/"
          chmod -R u+w "$out"
          rm "$out/lazy-lock.json"
          ln -s ${mutableState}/nvim/lazy-lock.json "$out/lazy-lock.json"
          rm "$out/lua/plugins/dankcolors.lua"
          ln -s ${mutableState}/nvim/lua/plugins/dankcolors.lua "$out/lua/plugins/dankcolors.lua"
        '';
      in
      {
        home = {
          username = "mariano";
          homeDirectory = home;
          stateVersion = "25.11";
          sessionPath = [
            "$HOME/.opencode/bin"
            "$HOME/.local/bin"
            "$HOME/.lmstudio/bin"
            "$HOME/.nvm/versions/node/v24.16.0/bin"
          ];
          sessionVariables = {
            BROWSER = "google-chrome-stable";
            DEFAULT_BROWSER = "google-chrome.desktop";
            EDITOR = "nvim";
            SHELL = "/run/current-system/sw/bin/zsh";
            VISUAL = "nvim";
          };
        };

        programs.home-manager.enable = true;

        # Seed writable application state once, then leave later live changes
        # alone. This keeps the same initial configuration on a new host without
        # tying either machine to the source checkout's absolute path.
        home.activation.seedMutableDotfiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
          seed_mutable() {
            source=$1
            target=$2
            if [ ! -e "$target" ]; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -a "$source" "$target"
            fi
            # Nix store sources are read-only. Repair both freshly seeded and
            # previously seeded state so applications can update it in place.
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+rwX "$target"
          }

          ${lib.concatMapStringsSep "\n" (path: ''
            seed_mutable ${
              lib.escapeShellArg "${mutableDotfileSeed}/${path}"
            } ${lib.escapeShellArg "${mutableState}/${path}"}
          '') mutableDotfiles}
        '';

        # These settings are policy rather than user preferences: they keep one
        # visual owner, enable Bonhart's biometric surfaces, and prevent mutable
        # user Matugen templates or third-party launcher entries from executing
        # as part of a theme switch. Preserve every unrelated DMS preference.
        home.activation.enforceDmsConsistency = lib.hm.dag.entryAfter [ "seedMutableDotfiles" ] ''
          settings=${lib.escapeShellArg "${mutableState}/dms/settings.json"}
          if ${pkgs.jq}/bin/jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
            temporary="$(${pkgs.coreutils}/bin/mktemp)"
            ${pkgs.jq}/bin/jq --argjson fingerprint ${builtins.toJSON fingerprintEnabled} '
              .runUserMatugenTemplates = false
              | .showThirdPartyPlugins = false
              | .searchAppActions = true
              | .launcherStyle = "full"
              | .dankLauncherV2Size = "medium"
              | .gtkThemingEnabled = true
              | .qtThemingEnabled = false
              | .matugenTemplateGtk = true
              | .greeterEnableFprint = $fingerprint
              | .enableFprint = $fingerprint
              | .lockBeforeSuspend = true
              | .animationSpeed = 4
              | .customAnimationDuration = 40
              | .syncComponentAnimationSpeeds = true
              | .popoutAnimationSpeed = 4
              | .popoutCustomAnimationDuration = 40
              | .modalAnimationSpeed = 4
              | .modalCustomAnimationDuration = 40
              | .notificationAnimationSpeed = 4
              | .notificationCustomAnimationDuration = 60
              | .controlCenterShowIdleInhibitorIcon = false
              | .controlCenterShowDoNotDisturbIcon = false
              | .fadeToLockEnabled = false
              | .fadeToLockGracePeriod = 0
              | .lockScreenShowPowerActions = false
              | .lockScreenShowSystemIcons = false
              | .lockScreenShowTime = true
              | .lockScreenShowDate = false
              | .lockScreenShowProfileImage = false
              | .lockScreenShowPasswordField = true
              | .lockScreenShowMediaPlayer = false
              | .lockScreenNotificationMode = 0
              | .lockScreenVideoEnabled = false
            ' "$settings" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$settings"
            ${pkgs.coreutils}/bin/rm -f "$temporary"
          else
            echo "DMS settings are not valid JSON: $settings" >&2
            exit 1
          fi

          # System-wide plugin installation and mutable enablement are separate
          # in DMS. Keep the three reviewed launcher providers active on both
          # upgrades and fresh installs while preserving every other plugin's
          # settings.
          plugin_settings=${lib.escapeShellArg "${mutableState}/dms/plugin-settings.json"}
          if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$plugin_settings" >/dev/null 2>&1; then
            echo "DMS plugin settings are not valid JSON: $plugin_settings" >&2
            exit 1
          fi
          temporary="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.jq}/bin/jq '
            .systemMenu.enabled = true
            | .themePicker.enabled = true
            | .wallpaperPicker.enabled = true
          ' "$plugin_settings" > "$temporary"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$plugin_settings"
          ${pkgs.coreutils}/bin/rm -f "$temporary"

          # Migrate installations whose seeded DMS policy left every automatic
          # privacy action disabled. Apply this once so Power & Sleep remains a
          # real user-facing settings surface after the secure defaults land.
          idle_policy_marker=${lib.escapeShellArg "${mutableState}/dms/.secure-idle-v1"}
          if [ ! -e "$idle_policy_marker" ]; then
            temporary="$(${pkgs.coreutils}/bin/mktemp)"
            ${pkgs.jq}/bin/jq '
              .acLockTimeout = 600
              | .acPostLockMonitorTimeout = 60
              | .batteryLockTimeout = 300
              | .batteryPostLockMonitorTimeout = 30
            ' "$settings" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$settings"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/touch "$idle_policy_marker"
            ${pkgs.coreutils}/bin/rm -f "$temporary"
          fi

          # This is a one-time layout migration, not a permanent policy. It
          # replaces the duplicate idle pill with the consolidated Focus panel
          # and adds the explicit-run speed test while preserving every other
          # bar choice and its order.
          qol_bar_marker=${lib.escapeShellArg "${mutableState}/dms/.qol-bar-v1"}
          if [ ! -e "$qol_bar_marker" ]; then
            plugin_settings=${lib.escapeShellArg "${mutableState}/dms/plugin-settings.json"}
            if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$plugin_settings" >/dev/null 2>&1; then
              echo "DMS plugin settings are not valid JSON: $plugin_settings" >&2
              exit 1
            fi
            temporary="$(${pkgs.coreutils}/bin/mktemp)"
            ${pkgs.jq}/bin/jq '
              def widget_id: if type == "object" then .id else . end;
              .barConfigs |= map(
                .rightWidgets as $widgets
                | .rightWidgets = (
                    [$widgets[]? | select(widget_id == "codexBar")]
                    + [
                        {"id": "focus", "enabled": true},
                        {"id": "networkSpeed", "enabled": true}
                      ]
                    + [$widgets[]? | select(
                        widget_id != "codexBar"
                        and widget_id != "focus"
                        and widget_id != "networkSpeed"
                        and widget_id != "idleInhibitor"
                      )]
                  )
              )
            ' "$settings" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$settings"
            ${pkgs.jq}/bin/jq '
              .focus.enabled = true
              | .networkSpeed.enabled = true
            ' "$plugin_settings" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$plugin_settings"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/touch "$qol_bar_marker"
            ${pkgs.coreutils}/bin/rm -f "$temporary"
          fi

          # Keep the Vicinae application launcher and dedicated system-menu
          # bindings consistent even if an older DMS generation seeded this
          # mutable file.
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 \
            ${dotfiles}/niri/dms/binds.kdl \
            ${lib.escapeShellArg "${mutableState}/niri/dms/binds.kdl"}
        '';

        # KScreen/KWin output state cannot configure niri and used to compete
        # with DMS's checked-in outputs.kdl. Archive the two known stores once
        # instead of deleting user state.
        home.activation.retireKdeDisplayState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          archive=${lib.escapeShellArg "${mutableState}/retired-kde-display"}
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$archive"

          retire_display_state() {
            source=$1
            destination=$2
            if { [ -e "$source" ] || [ -L "$source" ]; } && [ ! -e "$destination" ]; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$source" "$destination"
            fi
          }

          retire_display_state "$HOME/.local/share/kscreen" "$archive/kscreen"
          retire_display_state "$HOME/.config/kwinoutputconfig.json" "$archive/kwinoutputconfig.json"
        '';

        # Vicinae owns a writable settings file so its GUI can keep managing
        # preferences. Merge only the two palette pointers instead of replacing
        # that file with an immutable Home Manager link.
        home.activation.enforceVicinaeTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          settings="$HOME/.config/vicinae/settings.json"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/vicinae"
          temporary="$(${pkgs.coreutils}/bin/mktemp)"
          source_json="$(${pkgs.coreutils}/bin/mktemp)"
          if [ -f "$settings" ]; then
            # Vicinae prefixes its otherwise-valid JSON with documentation
            # comments. Strip only that generated header before the merge.
            ${pkgs.gnused}/bin/sed -n '/^[[:space:]]*{/,$p' "$settings" > "$source_json"
          else
            ${pkgs.jq}/bin/jq -n '{
              "$schema": "https://vicinae.com/schemas/config.json",
              theme: {}
            }' > "$source_json"
          fi
          if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$source_json" >/dev/null 2>&1; then
            echo "Vicinae settings are not valid JSON after the generated header: $settings" >&2
            ${pkgs.coreutils}/bin/rm -f "$temporary" "$source_json"
            exit 1
          fi
          ${pkgs.jq}/bin/jq '
            .theme.light.name = "themeport"
            | .theme.dark.name = "themeport"
          ' "$source_json" > "$temporary"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$settings"
          ${pkgs.coreutils}/bin/rm -f "$temporary" "$source_json"
        '';

        # Older Themeport generations stored the active image inside a
        # per-theme subdirectory. Move DMS's three remembered wallpaper slots
        # to their equivalent flat catalog paths so DankDash immediately sees
        # every available image after an upgrade.
        home.activation.migrateDmsWallpaperLibrary = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          session=${lib.escapeShellArg "${mutableState}/dms/session.json"}

          migrate_wallpaper_key() {
            key=$1
            value=$(${pkgs.jq}/bin/jq -r --arg key "$key" '.[$key] // ""' "$session")
            prefix="$HOME/Pictures/Wallpapers/themeport/"
            case "$value" in
              "$prefix"*/*)
                relative=''${value#"$prefix"}
                theme=''${relative%%/*}
                filename=''${relative#*/}
                canonical="$HOME/Pictures/Wallpapers/$theme--$filename"
                if [ -f "$canonical" ]; then
                  temporary="$(${pkgs.coreutils}/bin/mktemp)"
                  ${pkgs.jq}/bin/jq --arg key "$key" --arg value "$canonical" \
                    '.[$key] = $value' "$session" > "$temporary"
                  $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$session"
                  ${pkgs.coreutils}/bin/rm -f "$temporary"
                fi
                ;;
            esac
          }

          if ${pkgs.jq}/bin/jq -e 'type == "object"' "$session" >/dev/null 2>&1; then
            migrate_wallpaper_key wallpaperPath
            migrate_wallpaper_key wallpaperPathLight
            migrate_wallpaper_key wallpaperPathDark
          fi
        '';

        programs.zsh = {
          enable = true;
          enableCompletion = true;
          dotDir = config.home.homeDirectory;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          oh-my-zsh = {
            enable = true;
            theme = "robbyrussell";
            plugins = [
              "git"
              "sudo"
            ];
          };
          initContent = ''
            export PATH=/home/mariano/.opencode/bin:$PATH

            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

            if [ -x "$HOME/.lmstudio/bin/lms" ]; then
              path=("$HOME/.lmstudio/bin" $path)
            fi

            eval "$(${pkgs.mise}/bin/mise activate zsh)"
          '';
        };

        xdg.enable = true;
        xdg.configFile = {
          "ghostty/config".source = ../../dotfiles/ghostty/config.ghostty;
          "ghostty/config.ghostty".source = ../../dotfiles/ghostty/config.ghostty;
          "alacritty/alacritty.toml".source = ../../dotfiles/alacritty/alacritty.toml;

          "niri/config.kdl".source = ../../dotfiles/niri/config.kdl;
          "niri/manifesto.kdl".source = ../../dotfiles/niri/manifesto.kdl;
          "niri/style-toggles.kdl".source = ../../dotfiles/niri/style-toggles.kdl;
          "niri/themeport.kdl".source = ../../dotfiles/niri/themeport.kdl;
          "niri/voice.kdl".source = ../../dotfiles/niri/voice.kdl;
          "niri/dms/alttab.kdl".source = mutableDotfile "niri/dms/alttab.kdl";
          "niri/dms/binds.kdl".source = mutableDotfile "niri/dms/binds.kdl";
          "niri/dms/colors.kdl".source = mutableDotfile "niri/dms/colors.kdl";
          "niri/dms/cursor.kdl".source = mutableDotfile "niri/dms/cursor.kdl";
          "niri/dms/layout.kdl".source = mutableDotfile "niri/dms/layout.kdl";
          "niri/dms/outputs.kdl".source = mutableDotfile "niri/dms/outputs.kdl";
          "niri/dms/windowrules.kdl".source = mutableDotfile "niri/dms/windowrules.kdl";
          "niri/dms/wpblur.kdl".source = mutableDotfile "niri/dms/wpblur.kdl";
          "niri/toggles/gaps.kdl".source = mutableDotfile "niri/toggles/gaps.kdl";
          "niri/toggles/border.kdl".source = mutableDotfile "niri/toggles/border.kdl";
          "niri/toggles/radius.kdl".source = mutableDotfile "niri/toggles/radius.kdl";

          "matugen/config.toml".source = ../../dotfiles/matugen/config.toml;
          "matugen/templates/neovim-dankcolors.lua".source =
            ../../dotfiles/matugen/templates/neovim-dankcolors.lua;

          "DankMaterialShell/theme.json".source = mutableDotfile "dms/theme.json";
          "DankMaterialShell/themes/dms-ayu/theme.json".source =
            mutableDotfile "dms/themes/dms-ayu/theme.json";
          "DankMaterialShell/themes/themeport/theme.json".source = mutableDotfile "themeport/dms/theme.json";
          "DankMaterialShell/settings.json".source = mutableDotfile "dms/settings.json";
          "DankMaterialShell/plugin_settings.json".source = mutableDotfile "dms/plugin-settings.json";

          # AirPods need WirePlumber's AVRCP player so their stem gestures can
          # control MPRIS-aware players. Do not also enable mpris-proxy; upstream
          # warns that the two implementations conflict.
          "wireplumber/wireplumber.conf.d/51-bluez-avrcp.conf".source =
            ../../dotfiles/wireplumber/51-bluez-avrcp.conf;

          # Never restore a stored "off" profile for Bluetooth cards, or the
          # headset reconnects as a device with no sink and vanishes from the
          # output pickers.
          "wireplumber/wireplumber.conf.d/52-bluez-no-off-profile.conf".source =
            ../../dotfiles/wireplumber/52-bluez-no-off-profile.conf;

          "input-remapper-2/config.json".source = ../../dotfiles/input-remapper-2/config.json;
          "input-remapper-2/presets/AT Translated Set 2 keyboard/new preset.json".source =
            dotfiles + "/input-remapper-2/presets/AT Translated Set 2 keyboard/new preset.json";
          "input-remapper-2/presets/MX Keys Mini Keyboard/new preset.json".source =
            dotfiles + "/input-remapper-2/presets/MX Keys Mini Keyboard/new preset.json";
          "input-remapper-2/presets/vicinae-snippet-virtual-keyboard/new preset.json".source =
            dotfiles + "/input-remapper-2/presets/vicinae-snippet-virtual-keyboard/new preset.json";

          # settings.json is writable so Themeport and VS Code can edit
          # workbench.colorTheme without mutating the source checkout.
          "Code/User/settings.json".source = mutableDotfile "vscode/User/settings.json";
          "Code/User/keybindings.json".source = ../../dotfiles/vscode/User/keybindings.json;

          # Themeport rendered state is writable and host-local.
          "ghostty/themes/themeport".source = mutableDotfile "themeport/ghostty/themes/themeport";
          "alacritty/themeport.toml".source = mutableDotfile "themeport/alacritty/themeport.toml";
          "btop/themes/themeport.theme".source = mutableDotfile "themeport/btop/themes/themeport.theme";
          "tmux/themeport.conf".source = mutableDotfile "themeport/tmux/themeport.conf";
        }
        // lib.optionalAttrs (builtins.pathExists ../../dotfiles/vscode/User/prompts) {
          "Code/User/prompts".source = ../../dotfiles/vscode/User/prompts;
        };

        # Vicinae 0.23 discovers TOML themes from XDG_DATA_HOME. The target is
        # writable state, so Themeport can update it live on every switch.
        xdg.dataFile."vicinae/themes/themeport.toml".source =
          mutableDotfile "themeport/vicinae/themeport.toml";

        home.file = {
          ".face".source = config.lib.file.mkOutOfStoreSymlink "${home}/Pictures/profile.jpg";
          ".config/nvim" = {
            source = nvimConfig;
            # Keep the configuration declarative while letting lazy.nvim update
            # its lockfile and DMS rewrite the generated palette through the
            # two out-of-store symlinks above.
            force = true;
          };
          ".local/state/DankMaterialShell/session.json".source = mutableDotfile "dms/session.json";
          "Fonts/.keep".text = "";
          ".local/share/fonts/.keep".text = "";
          "Pictures/Wallpapers" = {
            source = wallpaperLibrary;
            recursive = true;
          };
        };
      };
  };

  system.activationScripts.fixVscodeConfigOwnership = lib.stringAfter [ "users" ] ''
    if [ -d ${home}/.config/Code ]; then
      ${pkgs.coreutils}/bin/chown -R mariano:users ${home}/.config/Code
      ${pkgs.coreutils}/bin/chmod -R u+rwX ${home}/.config/Code
    fi
  '';
}
