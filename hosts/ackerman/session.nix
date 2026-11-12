# ackerman's desktop session (Mariano, 2026-11-09): stock niri with stock DMS, and nothing of his
# niri + Folio desktop (modules/nixos/niri-folio.nix and dotfiles-niri/ stay in git, unused here).
#
# niri reads DMS's own niri config, as `dms setup` writes it (config.kdl), which includes the files
# DMS keeps in ~/.config/niri/dms (seeded here once from DMS's templates, then DMS's), then
# ackerman.kdl (the M5 Max's GPU and panel, no motion, bonhart's input feel, his app keys), and last
# local.kdl, his own (created empty once). DMS runs on its defaults; only the policy keys below are
# set. No wallpaper.
{
  lib,
  pkgs,
  dms,
  quickshell,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  embedded = "${dms}/core/internal/config/embedded";

  # DMS as its flake builds it, with one policy change (as niri.nix had it): no plugins run from
  # ~/.config/DankMaterialShell/plugins, which anything could write (no runtime-downloaded code)
  dmsShell = dms.packages.${system}.dms-shell.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      chmod -R u+w "$out/share/quickshell/dms/Services"
      substituteInPlace "$out/share/quickshell/dms/Services/PluginService.qml" \
        --replace-fail 'userWatcher.folder = Paths.toFileUrl(root.pluginDirectory);' 'userWatcher.folder = "";' \
        --replace-fail 'const userList = snapshotModel(userWatcher, "user");' 'const userList = [];' \
        --replace-fail 'const userUrl = Paths.toFileUrl(root.pluginDirectory);' 'const userUrl = "";'
    '';
  });

  # DMS's niri config, then ackerman.kdl. Without DMS's dms/input.kdl: niri can't switch a flag
  # like natural-scroll off again in a later include, so input is ackerman.kdl's alone.
  niriConfig = pkgs.runCommandLocal "niri-config-dms" { } ''
    grep -v 'include optional=true "dms/input.kdl"' ${embedded}/niri.kdl > $out
    printf '\n// ackerman (hosts/ackerman/session.nix)\ninclude "ackerman.kdl"\n' >> $out
    printf '// His own niri changes, last: a plain file, not home-manager'"'"'s\ninclude optional=true "local.kdl"\n' >> $out
  '';

  # DMS's includes as `dms setup` writes them (the terminal: Ghostty)
  dmsIncludes = pkgs.runCommandLocal "niri-dms-includes" { } ''
    mkdir -p $out
    sed 's|{{TERMINAL_COMMAND}}|ghostty|' ${embedded}/niri-binds.kdl > $out/binds.kdl
    cp ${embedded}/niri-colors.kdl $out/colors.kdl
    cp ${embedded}/niri-layout.kdl $out/layout.kdl
    cp ${embedded}/niri-alttab.kdl $out/alttab.kdl
  '';

  # Policy, not look: no user Matugen templates or third-party launcher entries, no suspend from the
  # shell (the M5 Max has no hibernation; the bring-up decides its suspend policy), lock before
  # sleep, and no motion (Mariano, 2026-11-08). Everything else is DMS's default.
  dmsPolicy = ''
    .runUserMatugenTemplates = false
    | .showThirdPartyPlugins = false
    | .acSuspendTimeout = 0
    | .batterySuspendTimeout = 0
    | .lockBeforeSuspend = true
    | .animationSpeed = 4
    | .customAnimationDuration = 0
    | .syncComponentAnimationSpeeds = true
    | .reduceMotion = true
    | .springBounce = 0
    | .popoutAnimationSpeed = 4
    | .popoutCustomAnimationDuration = 0
    | .modalAnimationSpeed = 4
    | .modalCustomAnimationDuration = 0
    | .notificationAnimationSpeed = 4
    | .notificationCustomAnimationDuration = 0
    | .fadeToLockEnabled = false
    | .fadeToLockGracePeriod = 0
  '';
in
{
  imports = [
    dms.nixosModules.dank-material-shell
    # Alt+Shift+3/4/5 (grim, slurp, wf-recorder)
    ../../modules/nixos/capture.nix
  ];

  programs.dank-material-shell = {
    enable = true;
    package = dmsShell;
    quickshell.package = quickshell.packages.${system}.default;
    # dgop is not in the nixpkgs pin
    enableSystemMonitoring = false;
    # The package's own unit (below), not the module's: the module's has an empty PATH
    systemd.enable = false;
  };

  # DMS with the session: niri-session starts graphical-session.target. The PATH is the session's,
  # complete, because DMS hands it to the apps it launches (/run/wrappers first for sudo).
  systemd.user.services.dms = {
    overrideStrategy = "asDropin";
    wantedBy = [ "graphical-session.target" ];
    path = [
      "/run/wrappers"
      "%h/.local"
      "/etc/profiles/per-user/mariano"
      "/run/current-system/sw"
    ];
    serviceConfig.CPUWeight = 150;
  };

  programs.dconf.enable = true;

  # themeport.nix publishes Folio's appearance for the GNOME machines' greeter; ackerman has neither
  # (and the unit failed here: azure-folio expects uid 1000)
  systemd.services.azure-folio-greeter-state.enable = false;
  systemd.paths.azure-folio-greeter-state.enable = false;

  # DMS's lock screen authenticates through /etc/pam.d/dankshell when it exists (otherwise through a
  # stack `dms auth resolve-lock` writes under ~/.local/state): NixOS's password stack
  security.pam.services.dankshell = { };

  environment.systemPackages = with pkgs; [
    brightnessctl
    libnotify
    playerctl
    wtype
    xwayland-satellite
  ];

  home-manager.users.mariano =
    { lib, ... }:
    {
      xdg.configFile = {
        "niri/config.kdl".source = niriConfig;
        "niri/ackerman.kdl".source = ./files/niri/ackerman.kdl;
      };

      # DMS's niri includes are DMS's to rewrite: writable copies, seeded where none is (or where a
      # link from the niri + Folio days was)
      home.activation.seedDmsNiriIncludes = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        d=$HOME/.config/niri/dms
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$d"
        for f in binds colors layout alttab; do
          if [ -L "$d/$f.kdl" ] || [ ! -e "$d/$f.kdl" ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$d/$f.kdl"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${dmsIncludes}/$f.kdl "$d/$f.kdl"
          fi
        done
      '';

      # ~/.config/niri/local.kdl: Mariano's (and his on-box agent's) place to change niri, included
      # last; created empty once, never touched again
      home.activation.niriLocal = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        f=$HOME/.config/niri/local.kdl
        if [ ! -e "$f" ] && [ ! -L "$f" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 /dev/null "$f"
        fi
      '';

      # DMS's settings: its own file (DMS stores only what differs from its defaults), plus the policy
      home.activation.dmsPolicy = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        s=$HOME/.config/DankMaterialShell/settings.json
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$s")"
        if [ -L "$s" ]; then $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$s"; fi
        if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$s" >/dev/null 2>&1; then
          [ -e "$s" ] && $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv -f "$s" "$s.broken-$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
          [ -z "$DRY_RUN_CMD" ] && echo '{}' > "$s"
        fi
        if [ -z "$DRY_RUN_CMD" ]; then
          t=$(${pkgs.coreutils}/bin/mktemp "$s.XXXXXX")
          ${pkgs.jq}/bin/jq '${dmsPolicy}' "$s" > "$t" && ${pkgs.coreutils}/bin/chmod 0600 "$t" && ${pkgs.coreutils}/bin/mv -f "$t" "$s"
        fi
      '';
    };
}
