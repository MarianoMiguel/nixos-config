{ config, lib, pkgs, quickshell, ... }:

# Folio's login screen (dotfiles/quickshell/folio-greeter). Off until the
# owner has tried it in person: with mariano.folio.greeter.enable false this
# module changes nothing.
#
# On, it takes greetd's default_session from DMS's greeter: greetd runs a bare
# niri (no binds, nothing to launch) that runs the Folio greeter in Quickshell.
# DMS's greeter stays installed and configured as the way back: when the
# Folio greeter ends without starting a session (it crashed, failed to load,
# or Ctrl+Alt+Backspace was pressed), the same greetd session hands over to
# DMS's greeter, so signing in never depends on Folio. Ctrl+Alt+F2 still
# opens a text console.
#
# The greeter user never reads the home directory. Its palette and plate are
# the selection azure-folio already publishes world-readable for greeters
# (/var/lib/azure-folio/appearance.json, modules/nixos/themeport.nix): the
# wrapper gives the greeter a HOME in its runtime directory where Folio's
# Theme finds that file at the path it always reads. Art and fonts come from
# the Nix store; sessions from services.displayManager.
let
  cfg = config.mariano.folio.greeter;
  dms = config.programs.dms-greeter;
  system = pkgs.stdenv.hostPlatform.system;
  qs = quickshell.packages.${system}.default;
  niri = config.programs.niri.package;
  folio = pkgs.callPackage ../../packages/folio-shell.nix { };
  xkb = config.services.xserver.xkb;
  sessions = "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
  defaultSession = if config.services.displayManager.defaultSession != null then config.services.displayManager.defaultSession else "niri";

  # The greeter's Quickshell config: its own module plus Folio's Common,
  # Widgets, Services and compiled shaders from the Folio package.
  greeter = pkgs.runCommand "folio-greeter" { } ''
    dir=$out/share/folio-greeter
    mkdir -p "$dir/Modules/Greeter"
    for d in Common Widgets Services shaders; do cp -r ${folio}/share/folio-shell/$d "$dir/"; done
    cp ${../../dotfiles/quickshell/folio-greeter/shell.qml} "$dir/shell.qml"
    cp ${../../dotfiles/quickshell/folio-greeter/Modules/Greeter}/*.qml "$dir/Modules/Greeter/"
    (cd "$dir/Modules/Greeter" && for f in *.qml; do echo "''${f%.qml} 1.0 $f"; done) > "$dir/Modules/Greeter/qmldir"
  '';

  # niri runs this; when Quickshell exits (after greetd took the session,
  # or not), niri goes too and the wrapper decides what comes next.
  run = pkgs.writeShellScript "folio-greeter-run" ''
    ${qs}/bin/qs -p ${greeter}/share/folio-greeter
    ${niri}/bin/niri msg action quit --skip-confirmation
  '';

  niriConfig = pkgs.writeText "folio-greeter-niri.kdl" ''
    // Folio's login screen: niri for the greeter alone. No binds but the way
    // out, so nothing can be launched before signing in.
    hotkey-overlay {
        skip-at-startup
    }
    input {
        keyboard {
            xkb {
                layout "${xkb.layout}"
                variant "${xkb.variant}"
                options "${xkb.options}"
            }
        }
        touchpad {
            tap
        }
    }
    cursor {
        xcursor-theme "Adwaita"
        xcursor-size 24
        hide-when-typing
    }
    gestures {
        hot-corners {
            off
        }
    }
    layout {
        background-color "#101d33"
    }
    binds {
        // Back to DMS's greeter, in the same greetd session.
        Ctrl+Alt+BackSpace allow-inhibiting=false { quit skip-confirmation=true; }
    }
    spawn-at-startup "${run}"
  '';

  # What runs when the Folio greeter did not start a session: DMS's greeter,
  # exactly as programs.dms-greeter would run it, else greetd's own agreety.
  dmsCompositor =
    if dms.compositor.package != null then dms.compositor.package
    else lib.attrByPath [ "programs" dms.compositor.name "package" ] pkgs.${dms.compositor.name} config;
  fallback =
    if dms.enable then
      pkgs.writeShellScript "folio-greeter-fallback" ''
        export PATH=$PATH:${lib.makeBinPath [ dms.quickshell.package dmsCompositor pkgs.glib ]}
        exec ${lib.escapeShellArgs ([ "${dms.package}/bin/dms-greeter" "--cache-dir" "/var/lib/dms-greeter" "--command" dms.compositor.name ]
          ++ lib.optionals (dms.compositor.customConfig != "") [ "-C" "${pkgs.writeText "dms-greeter-compositor-config" dms.compositor.customConfig}" ]
          ++ lib.optionals dms.logs.save [ "--debug" ])} ${lib.optionalString dms.logs.save "> ${dms.logs.path} 2>&1"}
      ''
    else
      pkgs.writeShellScript "folio-greeter-fallback" ''
        exec ${pkgs.greetd}/bin/agreety --cmd ${lib.escapeShellArg defaultSession}
      '';

  session = pkgs.writeShellScript "folio-greeter-session" ''
    # greetd's default_session: the Folio greeter in a bare niri, then DMS's
    # greeter if no session was started.
    base=''${XDG_RUNTIME_DIR:-}
    if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then base=''${TMPDIR:-/tmp}; fi
    if state=$(${pkgs.coreutils}/bin/mktemp -d "$base/folio-greeter.XXXXXX"); then
      home=$state/home
      ${pkgs.coreutils}/bin/mkdir -p "$home/.local/state/nixos-config/azure-folio" "$home/.config" "$home/.cache"
      ${pkgs.coreutils}/bin/ln -s /var/lib/azure-folio/appearance.json "$home/.local/state/nixos-config/azure-folio/selection.json"
      ${pkgs.coreutils}/bin/env \
        HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" XDG_STATE_HOME="$home/.local/state" \
        FOLIO_GREETER_STATE="$state" \
        FOLIO_GREETER_SESSIONS=${lib.escapeShellArg sessions} \
        FOLIO_GREETER_DEFAULT_SESSION=${lib.escapeShellArg defaultSession} \
        FOLIO_GREETER_USER=${lib.escapeShellArg cfg.user} \
        XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QT_NO_XDG_DESKTOP_PORTAL=1 \
        PATH="${lib.makeBinPath [ niri qs pkgs.coreutils pkgs.gawk pkgs.getent pkgs.systemd ]}:/run/current-system/sw/bin" \
        ${niri}/bin/niri -c ${niriConfig}
      launched=$(${pkgs.coreutils}/bin/cat "$state/launched" 2>/dev/null)
      ${pkgs.coreutils}/bin/rm -rf "$state"
      case "$launched" in launched*) exit 0 ;; esac
    fi
    echo "folio-greeter: no session was started; handing over to ${if dms.enable then "DMS's greeter" else "agreety"}" >&2
    exec ${fallback}
  '';
in
{
  options.mariano.folio.greeter = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use Folio's login screen instead of DMS's greeter. Off until tried in
        person; DMS's greeter remains the fallback when it is on.
      '';
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "mariano";
      description = "The user the login screen offers first.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = greeter;
      defaultText = lib.literalMD "the greeter built from `dotfiles/quickshell/folio-greeter`";
      description = "The greeter's Quickshell config (for tests and inspection).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.greetd.enable;
        message = "mariano.folio.greeter needs greetd (services.greetd.enable).";
      }
      {
        assertion = config.programs.niri.enable;
        message = "mariano.folio.greeter runs inside niri (programs.niri.enable).";
      }
    ];
    services.greetd.settings.default_session.command = lib.mkForce "${session}";
  };
}
