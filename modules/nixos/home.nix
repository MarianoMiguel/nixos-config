{ lib, pkgs, ... }:

let
  home = "/home/mariano";
  dotfiles = ../../dotfiles;
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-nixos";

    users.mariano = {
      home = {
        username = "mariano";
        homeDirectory = home;
        stateVersion = "25.11";
        sessionPath = [
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
        "niri/dms/alttab.kdl".source = ../../dotfiles/niri/dms/alttab.kdl;
        "niri/dms/binds.kdl".source = ../../dotfiles/niri/dms/binds.kdl;
        "niri/dms/colors.kdl".source = ../../dotfiles/niri/dms/colors.kdl;
        "niri/dms/cursor.kdl".source = ../../dotfiles/niri/dms/cursor.kdl;
        "niri/dms/layout.kdl".source = ../../dotfiles/niri/dms/layout.kdl;
        "niri/dms/outputs.kdl".source = ../../dotfiles/niri/dms/outputs.kdl;
        "niri/dms/windowrules.kdl".source = ../../dotfiles/niri/dms/windowrules.kdl;
        "niri/dms/wpblur.kdl".source = ../../dotfiles/niri/dms/wpblur.kdl;

        "matugen/config.toml".source = ../../dotfiles/matugen/config.toml;
        "matugen/templates/neovim-dankcolors.lua".source = ../../dotfiles/matugen/templates/neovim-dankcolors.lua;

        "DankMaterialShell/theme.json".source = ../../dotfiles/dms/theme.json;
        "DankMaterialShell/themes/dms-ayu/theme.json".source = ../../dotfiles/dms/themes/dms-ayu/theme.json;
        "DankMaterialShell/settings.json".source = ../../dotfiles/dms/settings.json;
        "DankMaterialShell/plugin_settings.json".source = ../../dotfiles/dms/plugin-settings.json;

        "input-remapper-2/config.json".source = ../../dotfiles/input-remapper-2/config.json;
        "input-remapper-2/presets/AT Translated Set 2 keyboard/new preset.json".source =
          dotfiles + "/input-remapper-2/presets/AT Translated Set 2 keyboard/new preset.json";
        "input-remapper-2/presets/MX Keys Mini Keyboard/new preset.json".source =
          dotfiles + "/input-remapper-2/presets/MX Keys Mini Keyboard/new preset.json";
        "input-remapper-2/presets/vicinae-snippet-virtual-keyboard/new preset.json".source =
          dotfiles + "/input-remapper-2/presets/vicinae-snippet-virtual-keyboard/new preset.json";

        "Code/User/settings.json".source = ../../dotfiles/vscode/User/settings.json;
        "Code/User/keybindings.json".source = ../../dotfiles/vscode/User/keybindings.json;
        "figma-linux/settings.json".text = builtins.toJSON {
          host = "127.0.0.1";
          port = "44950";
          app.fontDirs = [
            "/run/current-system/sw/share/X11/fonts"
            "/run/current-system/sw/share/fonts"
            "${home}/Fonts"
            "${home}/.local/share/fonts"
            "${home}/.fonts"
          ];
        };
      } // lib.optionalAttrs (builtins.pathExists ../../dotfiles/vscode/User/prompts) {
        "Code/User/prompts".source = ../../dotfiles/vscode/User/prompts;
      };

      home.file = {
        ".config/nvim" = {
          source = ../../dotfiles/nvim;
          recursive = true;
        };
        ".local/state/DankMaterialShell/session.json".source = ../../dotfiles/dms/session.json;
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
