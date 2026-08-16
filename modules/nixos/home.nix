{ lib, pkgs, ... }:

let
  home = "/home/mariano";
  dotfiles = ../../dotfiles;
  mutableState = "${home}/.local/state/nixos-config/dotfiles";
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
    "nvim/lua/plugins/dankcolors.lua"
    "themeport"
    "vscode/User/settings.json"
  ];
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
              lib.escapeShellArg (toString (dotfiles + "/${path}"))
            } ${lib.escapeShellArg "${mutableState}/${path}"}
          '') mutableDotfiles}
        '';

        programs.zsh = {
          enable = true;
          enableCompletion = true;
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
          "niri/themeport.kdl".source = ../../dotfiles/niri/themeport.kdl;
          "niri/dms/alttab.kdl".source = mutableDotfile "niri/dms/alttab.kdl";
          "niri/dms/binds.kdl".source = mutableDotfile "niri/dms/binds.kdl";
          "niri/dms/colors.kdl".source = mutableDotfile "niri/dms/colors.kdl";
          "niri/dms/cursor.kdl".source = mutableDotfile "niri/dms/cursor.kdl";
          "niri/dms/layout.kdl".source = mutableDotfile "niri/dms/layout.kdl";
          "niri/dms/outputs.kdl".source = mutableDotfile "niri/dms/outputs.kdl";
          "niri/dms/windowrules.kdl".source = mutableDotfile "niri/dms/windowrules.kdl";
          "niri/dms/wpblur.kdl".source = mutableDotfile "niri/dms/wpblur.kdl";

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

        home.file = {
          ".face".source = config.lib.file.mkOutOfStoreSymlink "${home}/Pictures/profile.jpg";
          ".config/nvim" = {
            source = nvimConfig;
            # Keep the configuration declarative while letting DMS rewrite its
            # generated palette through the one out-of-store symlink above.
            force = true;
          };
          ".local/state/DankMaterialShell/session.json".source = mutableDotfile "dms/session.json";
          "Fonts/.keep".text = "";
          ".local/share/fonts/.keep".text = "";
          "Pictures/Wallpapers" = {
            source = ../../assets/wallpapers;
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
