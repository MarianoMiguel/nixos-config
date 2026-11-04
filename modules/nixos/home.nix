{ config, lib, pkgs, ... }:

let
  home = "/home/mariano";
  dotfiles = ../../dotfiles;
  mutableState = "${home}/.local/state/nixos-config/dotfiles";
  folio = pkgs.callPackage ../../packages/azure-folio.nix { };
  # The gallery contains only this family's default blue/daylight plates.
  # The native picker applies the current ink and mode through azure-folio.
  wallpaperLibrary = pkgs.runCommandLocal "azure-folio-wallpapers" { } ''
    mkdir -p "$out"
    for art in ${folio}/share/azure-folio/art/*; do
      ln -s "$art/azure-light-desktop.png" "$out/$(basename "$art").png"
    done
  '';
  mutableDotfiles = [
    # The login screen's (DMS's greeter) settings and session; login-screen.nix
    # links them where the greeter looks and keeps its settings in line.
    "dms/session.json"
    "dms/settings.json"
    "nvim/lazy-lock.json"
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
          rm "$out/lua/plugins/themeport.lua"
          # Themeport renders this from the immutable, reviewed catalog; link
          # Neovim to that output directly.
          ln -s ${mutableState}/themeport/neovim/generated.lua "$out/lua/plugins/themeport.lua"
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
            # BROWSER stays unset; see the note in apps.nix, it breaks
            # xdg-settings' default-browser detection.
            DEFAULT_BROWSER = "google-chrome.desktop";
            EDITOR = "nvim";
            SHELL = "/run/current-system/sw/bin/zsh";
            VISUAL = "nvim";
          };
        };

        programs.home-manager.enable = true;

        # One typography and cursor for every toolkit. Themeport's kdeglobals,
        # the login screen and the terminal already use Inter and IBM Plex
        # Mono; without these keys GNOME, GTK apps and portals use Adwaita Sans.
        # The icon theme is deliberately absent: Themeport sets it per theme.
        dconf.settings."org/gnome/desktop/interface" = {
          font-name = "Inter 11";
          document-font-name = "Inter 11";
          monospace-font-name = "IBM Plex Mono 11";
          cursor-theme = "Adwaita";
          cursor-size = 24;
        };

        # systemd --user reads environment.d before the graphical session
        # starts, so this is the one place a PATH entry reaches everything:
        # units, GNOME Shell, the apps it launches and their terminals.
        # home.sessionPath above only reaches login shells, behind a guard
        # the graphical session inherits without the PATH it came with.
        systemd.user.sessionVariables.PATH = "$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.lmstudio/bin:$PATH";

        # Seed writable application state once, then leave later live changes
        # alone. This keeps the same initial configuration on a new host without
        # tying either machine to the source checkout's absolute path.
        home.activation.seedMutableDotfiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
          seed_mutable() {
            source=$1
            target=$2
            if [ -d "$source" ] && [ -d "$target" ]; then
              # Preserve live rendered state, but merge newly introduced seed
              # files into existing mutable directories on upgrades.
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -a -n "$source/." "$target/"
            elif [ ! -e "$target" ]; then
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

        # Shell memory: atuin makes history searchable (Ctrl+R) and keeps the
        # up arrow plain; zoxide learns directories from use (z, zi).
        programs.atuin = {
          enable = true;
          enableZshIntegration = true;
          flags = [ "--disable-up-arrow" ];
          settings = {
            update_check = false;
            # Local only until an account is registered with `atuin login`.
            auto_sync = false;
          };
        };
        programs.zoxide = {
          enable = true;
          enableZshIntegration = true;
        };

        programs.zsh = {
          enable = true;
          enableCompletion = true;
          dotDir = config.home.homeDirectory;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          # Run the Claude Code CLI with permission prompts skipped by default.
          # Escape with `command claude` or `\claude` for a prompted session.
          shellAliases.claude = "claude --dangerously-skip-permissions";
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
          # Qt and KDE applications (Dolphin, Kate, Kdenlive, Krita) read their
          # palette, fonts and icon theme from here through the KDE platform
          # theme, so they follow Themeport like GTK does.
          "kdeglobals".source = mutableDotfile "themeport/kdeglobals";
          # GTK 4 and libadwaita apps (Files, and with it the GNOME file
          # chooser behind the portal) read the palette's colors here, light
          # and dark in one file; GTK 3 apps get the current mode.
          "gtk-4.0/gtk.css".source = mutableDotfile "themeport/gtk-4.0/gtk.css";
          "gtk-3.0/gtk.css".source = mutableDotfile "themeport/gtk-3.0/gtk.css";
          # ChatGPT Community's omarchy-theme feature watches this conventional
          # path and reloads the generated palette in open windows.
          "omarchy/current/theme/codex-desktop.css".source =
            mutableDotfile "themeport/codex-desktop.css";
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
            # its lockfile and Themeport rewrite the generated palette through
            # the two out-of-store symlinks above.
            force = true;
          };
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
