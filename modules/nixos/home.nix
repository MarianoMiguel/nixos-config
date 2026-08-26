{ lib, pkgs, ... }:

let
  home = "/home/mariano";
  dotfiles = ../../dotfiles;
  mutableState = "${home}/.local/state/nixos-config/dotfiles";
  jsoncPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.commentjson ]);
  mutableDotfiles = [
    "nvim/lazy-lock.json"
    "vscode/User/settings.json"
  ];
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

        # Seed writable application state once, then leave later application
        # updates alone. This keeps the same starting point on fresh hosts.
        home.activation.seedMutableDotfiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
          seed_mutable() {
            source=$1
            target=$2
            if [ -d "$source" ] && [ -d "$target" ]; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -a -n "$source/." "$target/"
            elif [ ! -e "$target" ]; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -a "$source" "$target"
            fi
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+rwX "$target"
          }

          ${lib.concatMapStringsSep "\n" (path: ''
            seed_mutable ${
              lib.escapeShellArg "${mutableDotfileSeed}/${path}"
            } ${lib.escapeShellArg "${mutableState}/${path}"}
          '') mutableDotfiles}
        '';

        # Replace the former live palette synchronization with one fixed theme.
        # Every unrelated editor and launcher preference remains writable.
        home.activation.setStaticApplicationThemes = lib.hm.dag.entryAfter [ "seedMutableDotfiles" ] ''
          nvim_lock=${lib.escapeShellArg "${mutableState}/nvim/lazy-lock.json"}
          if ${pkgs.jq}/bin/jq -e 'type == "object"' "$nvim_lock" >/dev/null 2>&1; then
            temporary="$(${pkgs.coreutils}/bin/mktemp)"
            ${pkgs.jq}/bin/jq 'del(.ayu, .["base16-nvim"], .vesper)' "$nvim_lock" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$nvim_lock"
            ${pkgs.coreutils}/bin/rm -f "$temporary"
          fi

          vscode=${lib.escapeShellArg "${mutableState}/vscode/User/settings.json"}
          vscode_json="$(${pkgs.coreutils}/bin/mktemp)"
          if ${jsoncPython}/bin/python -c '
import commentjson, json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    document = commentjson.load(source)
with open(sys.argv[2], "w", encoding="utf-8") as target:
    json.dump(document, target)
' "$vscode" "$vscode_json" 2>/dev/null \
            && ${pkgs.jq}/bin/jq -e 'type == "object"' "$vscode_json" >/dev/null 2>&1; then
            temporary="$(${pkgs.coreutils}/bin/mktemp)"
            ${pkgs.jq}/bin/jq '
              del(
                .["vscode_custom_css.imports"],
                .["vscode_vibrancy.opacity"],
                .["vscode_vibrancy.theme"],
                .["window.autoDetectColorScheme"],
                .["window.systemColorTheme"],
                .["omarchyThemeSync.folderToVSCodeTheme"],
                .["omarchyThemeSync.defaultVSCodeTheme"],
                .["omarchyThemeSync.warnIfThemeMissing"],
                .["workbench.preferredDarkColorTheme"]
              )
              | .["workbench.colorTheme"] = "Catppuccin Mocha"
              | .["workbench.iconTheme"] = "catppuccin-mocha"
            ' "$vscode_json" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$vscode"
            ${pkgs.coreutils}/bin/rm -f "$temporary"
          fi
          ${pkgs.coreutils}/bin/rm -f "$vscode_json"

          vicinae="$HOME/.config/vicinae/settings.json"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/vicinae"
          source_json="$(${pkgs.coreutils}/bin/mktemp)"
          temporary="$(${pkgs.coreutils}/bin/mktemp)"
          if [ -f "$vicinae" ]; then
            ${pkgs.gnused}/bin/sed -n '/^[[:space:]]*{/,$p' "$vicinae" > "$source_json"
          else
            ${pkgs.jq}/bin/jq -n '{"$schema": "https://vicinae.com/schemas/config.json"}' > "$source_json"
          fi
          if ${pkgs.jq}/bin/jq -e 'type == "object"' "$source_json" >/dev/null 2>&1; then
            ${pkgs.jq}/bin/jq '
              .theme.light.name = "catppuccin-mocha"
              | .theme.dark.name = "catppuccin-mocha"
            ' "$source_json" > "$temporary"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 "$temporary" "$vicinae"
          fi
          ${pkgs.coreutils}/bin/rm -f "$source_json" "$temporary"
        '';

        # Move the old compositor/shell/theme state out of active config paths.
        # It remains recoverable under the NixOS state directory.
        home.activation.retireDesktopCustomization = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          archive=${lib.escapeShellArg "${mutableState}/retired-desktop-customization"}
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$archive"

          retire_path() {
            source=$1
            name=$2
            if { [ -e "$source" ] || [ -L "$source" ]; } && [ ! -e "$archive/$name" ]; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$source" "$archive/$name"
            fi
          }

          retire_path ${lib.escapeShellArg "${mutableState}/dms"} mutable-dms
          retire_path ${lib.escapeShellArg "${mutableState}/niri"} mutable-niri
          retire_path ${lib.escapeShellArg "${mutableState}/themeport"} mutable-themeport
          retire_path "$HOME/.config/DankMaterialShell" config-dms
          retire_path "$HOME/.config/niri" config-niri
          retire_path "$HOME/.config/matugen" config-matugen
          retire_path "$HOME/.config/themeport" config-themeport
          retire_path "$HOME/.config/omarchy" config-omarchy
          retire_path "$HOME/.local/share/themeport" data-themeport
          retire_path "$HOME/.cache/themeport" cache-themeport
          retire_path "$HOME/Pictures/Wallpapers/themeport" wallpapers-themeport
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

          "wireplumber/wireplumber.conf.d/51-bluez-avrcp.conf".source =
            ../../dotfiles/wireplumber/51-bluez-avrcp.conf;
          "wireplumber/wireplumber.conf.d/52-bluez-no-off-profile.conf".source =
            ../../dotfiles/wireplumber/52-bluez-no-off-profile.conf;

          "input-remapper-2/config.json".source = ../../dotfiles/input-remapper-2/config.json;
          "input-remapper-2/presets/AT Translated Set 2 keyboard/new preset.json".source =
            dotfiles + "/input-remapper-2/presets/AT Translated Set 2 keyboard/new preset.json";
          "input-remapper-2/presets/MX Keys Mini Keyboard/new preset.json".source =
            dotfiles + "/input-remapper-2/presets/MX Keys Mini Keyboard/new preset.json";
          "input-remapper-2/presets/vicinae-snippet-virtual-keyboard/new preset.json".source =
            dotfiles + "/input-remapper-2/presets/vicinae-snippet-virtual-keyboard/new preset.json";

          "Code/User/settings.json".source = mutableDotfile "vscode/User/settings.json";
          "Code/User/keybindings.json".source = ../../dotfiles/vscode/User/keybindings.json;
        }
        // lib.optionalAttrs (builtins.pathExists ../../dotfiles/vscode/User/prompts) {
          "Code/User/prompts".source = ../../dotfiles/vscode/User/prompts;
        };

        xdg.dataFile."vicinae/themes/catppuccin-mocha.toml".source =
          ../../dotfiles/vicinae/catppuccin-mocha.toml;

        home.file = {
          ".face".source = config.lib.file.mkOutOfStoreSymlink "${home}/Pictures/profile.jpg";
          ".config/nvim" = {
            source = nvimConfig;
            force = true;
          };
          "Fonts/.keep".text = "";
          ".local/share/fonts/.keep".text = "";
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
