{
  lib,
  pkgs,
  ...
}:

let
  # Pin the official Omarchy catalog so every reviewed theme and its bundled
  # wallpapers are available offline on both hosts and in the installer.
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
          '    # VS Code is themed by DMS Matugen; theme metadata never installs extensions.' \
        --replace-fail \
          '    apply_browsers(meta)' \
          '    # Browser managed policy is deliberately outside Themeport.'
      install -Dm0444 themeport.py "$out/share/themeport/themeport.py"
      cp -R templates "$out/share/themeport/templates"
      mkdir -p "$out/share/themeport/themes"
      cp -R ${omarchyThemes}/themes/. "$out/share/themeport/themes/"
      runHook postInstall
    '';
  };

  # Give the renderer exactly one DMS executable without pulling DMS into the
  # wrapper closure or exposing the rest of the user's PATH.
  dmsBridge = pkgs.writeShellScriptBin "dms" ''
    exec /run/current-system/sw/bin/dms "$@"
  '';

  safeRuntime = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.fzf
    pkgs.glib
    pkgs.python3
    pkgs.systemd
    pkgs.tmux
    dmsBridge
  ];

  # Theme switching is intentionally a closed catalog. The unwrapped renderer
  # still understands upstream formats, but this public command exposes only
  # themes reviewed and copied into the immutable Nix store. It does not expose
  # GitHub installs, galleries, URL handlers, arbitrary theme paths, VS Code
  # extension installation, or browser managed-policy refreshes.
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
            find "$wallpaper_root" -type f \( \
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
          resolved=$(realpath -e "$choice")
          root=$(realpath -e "$wallpaper_root")
          catalog_root=$(realpath -e "$trusted")
          case "$resolved" in
            "$root"/*) ;;
            "$catalog_root"/*)
              relative=''${resolved#"$catalog_root"/}
              theme=''${relative%%/*}
              destination="$wallpaper_root/themeport/$theme/''${resolved##*/}"
              mkdir -p "''${destination%/*}"
              install -m 0600 "$resolved" "$destination"
              resolved="$destination"
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
  environment.systemPackages = [
    themeport
    pkgs.yaru-theme
    pkgs.adwaita-icon-theme
  ];
}
