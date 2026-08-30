{
  lib,
  pkgs,
  quickshell,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  quickshellPackage = quickshell.packages.${system}.default;

  # Pin the official Omarchy catalog so every reviewed theme and its bundled
  # non-wordmark wallpapers are available offline on both hosts and in the installer.
  omarchyThemes = pkgs.fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "5d3299fb9426ae927b9fc7ef16c94bd334a90f01";
    hash = "sha256-smjQlpZd7mzMrxV6PQFjXRwVm0s8xybBthcIrvrTYUA=";
  };

  themeportUnwrapped = pkgs.stdenvNoCC.mkDerivation {
    pname = "themeport-unwrapped";
    version = "0.4.0";
    src = ../../tools/themeport;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      substituteInPlace themeport.py \
        --replace-fail \
          '    apply_vscode(state, meta)' \
          '    # VS Code is themed by DMS Matugen; theme metadata never installs extensions.'
      install -Dm0444 themeport.py "$out/share/themeport/themeport.py"
      cp -R templates "$out/share/themeport/templates"
      mkdir -p "$out/share/themeport/themes"
      cp -R ${omarchyThemes}/themes/. "$out/share/themeport/themes/"
      chmod -R u+w "$out/share/themeport/themes"
      find "$out/share/themeport/themes" -path '*/backgrounds/*' -type f \
        -iname '*omarchy*' -delete
      runHook postInstall
    '';
  };

  # Give the renderer exactly one DMS executable without exposing the rest of
  # the user's PATH. The DMS CLI delegates IPC transport to Quickshell, so make
  # qs visible only inside this bridge rather than in Themeport's outer PATH.
  dmsBridge = pkgs.writeShellScriptBin "dms" ''
    export PATH=${lib.makeBinPath [ quickshellPackage ]}
    exec /run/current-system/sw/bin/dms "$@"
  '';

  # Themeport only uses this bridge with Chrome's fixed policy-refresh flags.
  # Keeping Chrome itself out of the wrapper closure avoids duplicating its
  # large package while still allowing an already-running browser to update.
  chromeBridge = pkgs.writeShellScriptBin "google-chrome-stable" ''
    if [ "$#" -ne 2 ] \
      || [ "$1" != "--refresh-platform-policy" ] \
      || [ "$2" != "--no-startup-window" ]; then
      echo "This bridge only refreshes Chrome platform policy." >&2
      exit 2
    fi
    exec /run/current-system/sw/bin/google-chrome-stable "$@"
  '';

  # Themeport may select only its own generated Vicinae theme. Keep the full
  # launcher CLI out of the renderer's closed PATH.
  vicinaeBridge = pkgs.writeShellScriptBin "vicinae" ''
    if [ "$#" -ne 3 ] \
      || [ "$1" != "theme" ] \
      || [ "$2" != "set" ] \
      || [ "$3" != "themeport" ]; then
      echo "This bridge only selects Vicinae's generated Themeport palette." >&2
      exit 2
    fi
    exec /run/current-system/sw/bin/vicinae "$@"
  '';

  chromeThemeRequest = "/home/mariano/.local/state/nixos-config/dotfiles/themeport/chrome/color.json";
  chromeThemePolicy = "/var/lib/themeport/chrome-color.json";
  chromePolicySync = pkgs.writeShellApplication {
    name = "themeport-sync-chrome-policy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -eu

      input=${lib.escapeShellArg chromeThemeRequest}
      output=${lib.escapeShellArg chromeThemePolicy}
      output_dir=''${output%/*}

      # A missing request is normal on a fresh account; the path unit will run
      # this service as soon as Themeport creates it.
      [ -e "$input" ] || exit 0
      if [ -L "$input" ] \
        || [ "$(stat -c %F -- "$input")" != "regular file" ] \
        || [ "$(stat -c %U -- "$input")" != "mariano" ]; then
        echo "Refusing untrusted Chrome theme request: $input" >&2
        exit 1
      fi

      install -d -o root -g root -m 0755 "$output_dir"
      temporary=$(mktemp "$output_dir/.chrome-color.XXXXXX")
      trap 'rm -f "$temporary"' EXIT

      # Reconstruct the policy instead of copying it. Even if the user-side
      # JSON contains extra keys, only a valid six-digit theme color can cross
      # this privileged boundary.
      jq -e '
        if type == "object"
          and (.BrowserThemeColor | type == "string")
          and (.BrowserThemeColor | test("^#[0-9A-Fa-f]{6}$"))
        then {BrowserThemeColor: .BrowserThemeColor}
        else error("invalid BrowserThemeColor request")
        end
      ' "$input" > "$temporary"
      chmod 0644 "$temporary"
      mv -f "$temporary" "$output"
      trap - EXIT
    '';
  };

  safeRuntime = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.fzf
    pkgs.glib
    pkgs.python3
    pkgs.procps
    pkgs.systemd
    pkgs.tmux
    chromeBridge
    dmsBridge
    vicinaeBridge
  ];

  # Theme switching is intentionally a closed catalog. The unwrapped renderer
  # still understands upstream formats, but this public command exposes only
  # themes reviewed and copied into the immutable Nix store. It does not expose
  # GitHub installs, galleries, URL handlers, arbitrary theme paths, VS Code
  # extension installation, or arbitrary browser policy. Chrome receives only
  # the validated BrowserThemeColor key through the root-owned bridge below.
  themeport = pkgs.writeShellApplication {
    name = "themeport";
    runtimeInputs = safeRuntime;
    text = ''
      set -eu

      trusted=${themeportUnwrapped}/share/themeport/themes
      renderer=${themeportUnwrapped}/share/themeport/themeport.py
      export THEMEPORT_HOME="$trusted"
      export PATH=${lib.makeBinPath safeRuntime}

      usage() {
        cat <<'HELP'
Themeport (trusted catalog)

  themeport list
  themeport pick [--hold]
  themeport set THEME [--pair THEME] [--no-restart]
  themeport wallpapers [--all] [--list] [--hold]

Themes are shipped inside the immutable NixOS system. Online installs,
browser links, executable hooks and third-party catalogs are disabled.
HELP
      }

      validate_theme() {
        name=$1
        case "$name" in
          ""|*[!A-Za-z0-9_.-]*)
            echo "Invalid theme name: $name" >&2
            exit 2
            ;;
        esac
        if [ ! -d "$trusted/$name" ]; then
          echo "Theme is not in the trusted catalog: $name" >&2
          exit 2
        fi
      }

      command="''${1:-help}"
      [ "$#" -eq 0 ] || shift
      case "$command" in
        help|-h|--help)
          usage
          ;;
        list)
          [ "$#" -eq 0 ] || { usage >&2; exit 2; }
          exec python3 "$renderer" list
          ;;
        set)
          [ "$#" -ge 1 ] || { usage >&2; exit 2; }
          theme=$1
          shift
          validate_theme "$theme"
          pair=""
          no_restart=0
          while [ "$#" -gt 0 ]; do
            case "$1" in
              --pair)
                [ "$#" -ge 2 ] || { usage >&2; exit 2; }
                pair=$2
                validate_theme "$pair"
                shift 2
                ;;
              --no-restart)
                no_restart=1
                shift
                ;;
              *)
                usage >&2
                exit 2
                ;;
            esac
          done
          set -- "$theme"
          if [ -n "$pair" ]; then
            set -- "$@" --pair "$pair"
          fi
          if [ "$no_restart" -eq 1 ]; then
            set -- "$@" --no-restart
          fi
          exec python3 "$renderer" set "$@"
          ;;
        pick)
          hold=0
          if [ "''${1:-}" = --hold ] && [ "$#" -eq 1 ]; then
            hold=1
          elif [ "$#" -ne 0 ]; then
            usage >&2
            exit 2
          fi
          themes=$(find "$trusted" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
          choice=$(printf '%s\n' "$themes" | fzf --prompt='theme> ' --height=80% --border) || exit 0
          validate_theme "$choice"
          status=0
          python3 "$renderer" set "$choice" || status=$?
          if [ "$hold" -eq 1 ]; then
            printf '\nPress Enter to close.'
            read -r _ || true
          fi
          exit "$status"
          ;;
        wallpapers)
          all=0
          list=0
          hold=0
          for argument in "$@"; do
            case "$argument" in
              --all) all=1 ;;
              --list) list=1 ;;
              --hold) hold=1 ;;
              *) usage >&2; exit 2 ;;
            esac
          done
          # Offer both the user's own images and every wallpaper in the pinned
          # catalog. Avoid fzf preview shell templates entirely so a filename
          # can never become executable input.
          wallpaper_root="$HOME/Pictures/Wallpapers"
          mkdir -p "$wallpaper_root"
          images=$(
            find "$trusted" -mindepth 3 -path '*/backgrounds/*' -type f \( \
              -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
            \) -print
            find -L "$wallpaper_root" -type f \( \
              -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
            \) -print
          )
          images=$(printf '%s\n' "$images" | sort -u)
          if [ "$list" -eq 1 ]; then
            printf '%s\n' "$images"
            exit 0
          fi
          [ -n "$images" ] || { echo "No wallpapers found." >&2; exit 1; }
          # --all is retained as a harmless compatibility spelling; every
          # trusted and built-in wallpaper is already below this one root.
          : "$all"
          choice=$(printf '%s\n' "$images" | fzf --prompt='wallpaper> ' --height=80% --border) || exit 0
          case "$choice" in
            "$wallpaper_root"/*)
              [ -f "$choice" ] || { echo "Wallpaper no longer exists." >&2; exit 2; }
              # Preserve the library path instead of resolving its immutable
              # symlink. DMS uses the active file's parent as its gallery.
              resolved=$choice
              ;;
            "$trusted"/*)
              resolved=$(realpath -e "$choice")
              catalog_root=$(realpath -e "$trusted")
              case "$resolved" in
                "$catalog_root"/*) ;;
                *) echo "Wallpaper escaped the trusted catalog." >&2; exit 2 ;;
              esac
              relative=''${resolved#"$catalog_root"/}
              theme=''${relative%%/*}
              canonical="$wallpaper_root/$theme--''${resolved##*/}"
              if [ -f "$canonical" ]; then
                resolved=$canonical
              else
                destination="$wallpaper_root/themeport/$theme/''${resolved##*/}"
                mkdir -p "''${destination%/*}"
                install -m 0600 "$resolved" "$destination"
                resolved="$destination"
              fi
              ;;
            *) echo "Wallpaper escaped the trusted directory." >&2; exit 2 ;;
          esac
          status=0
          dms ipc call wallpaper set "$resolved" || status=$?
          if [ "$hold" -eq 1 ]; then
            printf '\nPress Enter to close.'
            read -r _ || true
          fi
          exit "$status"
          ;;
        install|browse|gallery|handle-url|preview|render)
          echo "Themeport '$command' is disabled: only immutable, reviewed themes are allowed." >&2
          exit 2
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  # Chrome reads managed policy from /etc, but Themeport runs as the desktop
  # user. Point Chrome at a root-owned file and have a sandboxed path service
  # validate the user-rendered color before updating it.
  environment.etc."opt/chrome/policies/managed/themeport-color.json".source = chromeThemePolicy;

  systemd.tmpfiles.rules = [ "d /var/lib/themeport 0755 root root -" ];

  systemd.services.themeport-chrome-policy = {
    description = "Validate and publish Themeport's Chrome color policy";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe chromePolicySync;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = "read-only";
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/themeport" ];
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };

  systemd.paths.themeport-chrome-policy = {
    description = "Watch Themeport's rendered Chrome color";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = chromeThemeRequest;
      Unit = "themeport-chrome-policy.service";
    };
  };

  environment.systemPackages = [
    themeport
    # Export previews and backgrounds at /run/current-system/sw/share/themeport
    # for the native DMS pickers; the command wrapper itself contains only bin/.
    themeportUnwrapped
    pkgs.yaru-theme
    pkgs.adwaita-icon-theme
  ];
}
