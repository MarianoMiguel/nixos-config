{
  config,
  lib,
  pkgs,
  ...
}:

# Interstellar's boot and disk-unlock screen: Plymouth with the
# "interstellar" theme (packages/plymouth-folio) instead of the bare console
# LUKS prompt, in the owner's look: Folio (plate and paper) or Lumen (its
# sky and page), light or dark, in one color.
#
# The look built into the initrd comes from the options below. With
# `followLook` (the default) the screen then follows the desktop without a
# rebuild: when the owner changes the look, a root service prints it from
# four checked values (theme, mode, color, Lumen's sky) and writes it to the boot
# partition as a small second initrd, which the default boot entry loads
# after NixOS's own. In the initrd, a check shows it only if every file in
# it is intact; otherwise Plymouth shows the built-in look
# (docs/folio-boot.md).
#
# The unlock path stays the one the Comet KVM already sees: Bonhart's initrd
# has no GPU driver, so the prompt is drawn on the firmware framebuffer
# (simpledrm) at its firmware mode, the same surface the text prompt uses,
# and keyboard input still reaches it as a plain USB keyboard with the US
# layout. Esc switches to the boot messages and back; `plymouth.enable=0` on
# the kernel command line (boot menu, `e`) skips Plymouth for one boot.
let
  cfg = config.mariano.folio.boot;
  host = config.networking.hostName;
  looks = {
    inks = [
      "azure"
      "cobalt"
      "slate"
    ];
    accents = [
      "blue"
      "purple"
      "pink"
      "red"
      "orange"
      "yellow"
      "green"
      "teal"
      "graphite"
    ];
  };
  color = names: lib.types.either (lib.types.enum names) (lib.types.strMatching "#[0-9a-fA-F]{6}");

  theme = pkgs.callPackage ../../packages/plymouth-folio {
    machineName = cfg.name;
    bootTheme = cfg.theme;
    folioMode = cfg.mode;
    bootColor = if cfg.theme == "folio" then cfg.ink else cfg.accent;
    folioArt = cfg.art;
    bootSky = cfg.sky;
  };

  # Where the published look lives: beside the entries that name it (an
  # entry's initrd paths are read from its own partition).
  loader = config.boot.loader;
  bootMount =
    if loader.systemd-boot.xbootldrMountPoint != null then
      loader.systemd-boot.xbootldrMountPoint
    else
      loader.efi.efiSysMountPoint;
  lookDir = "${bootMount}/EFI/interstellar";
  lookFile = "${lookDir}/look.cpio";
  entryLine = "initrd /EFI/interstellar/look.cpio";
  appearance = "/var/lib/azure-folio/appearance.json";

  # Plymouth looks for the published look first (in /run, where the
  # initrd's check puts it and where it survives the switch to the real
  # root), then falls back to plymouthd.defaults: the built-in look. Both
  # files serve the initrd and the running system (shutdown and restart).
  daemon = ''
    ShowDelay=0
    DeviceTimeout=8
    UseSimpledrm=1
  '';
  lookConf = pkgs.writeText "plymouthd.conf" ''
    [Daemon]
    Theme=interstellar-look
    ThemeDir=/run/interstellar/themes
    ${daemon}'';
  builtinConf = pkgs.writeText "plymouthd.defaults" ''
    [Daemon]
    Theme=interstellar
    ${daemon}'';

  installLook = pkgs.writeShellScript "interstellar-install-look" ''
    # Run by the boot loader installer after it wrote the entries.
    set -u
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnused
        pkgs.gnugrep
        pkgs.gawk
      ]
    }
    file=${lib.escapeShellArg lookFile}
    loaderConf=${lib.escapeShellArg "${loader.efi.efiSysMountPoint}/loader/loader.conf"}
    entries=${lib.escapeShellArg "${bootMount}/loader/entries"}

    # systemd-boot does not boot an entry whose initrd file is missing, and
    # skips an empty one. So the file exists before any entry names it: when
    # there is none yet, an empty one, meaning the built-in look until
    # interstellar-boot-look.service writes the owner's.
    if [ ! -e "$file" ]; then
      mkdir -p "''${file%/*}" && : > "$file.new" && sync "$file.new" && mv "$file.new" "$file" || {
        echo "interstellar: could not create $file; boot entries keep NixOS's initrd only" >&2
        exit 0
      }
    fi
    [ -f "$file" ] || exit 0

    # Only the default generation (and its specialisations) loads the look.
    # Older generations stay exactly as NixOS wrote them, so choosing the
    # previous generation at the boot menu never depends on this file.
    [ -f "$loaderConf" ] || exit 0
    default=$(sed -n 's/^default[[:space:]]\{1,\}//p' "$loaderConf")
    case "$default" in
      nixos*-generation-*.conf) ;;
      *) exit 0 ;;
    esac
    base=''${default%.conf}
    for entry in "$entries/$base.conf" "$entries/$base"-specialisation-*.conf; do
      [ -f "$entry" ] || continue
      grep -qxF ${lib.escapeShellArg entryLine} "$entry" && continue
      grep -q '^initrd ' "$entry" || continue
      awk -v line=${lib.escapeShellArg entryLine} \
        '{ print } /^initrd / && !done { print line; done = 1 }' "$entry" > "$entry.tmp" \
        && sync "$entry.tmp" && mv "$entry.tmp" "$entry" \
        || { rm -f "$entry.tmp"; echo "interstellar: could not add the look to $entry" >&2; }
    done
    sync -f "$file"
    exit 0
  '';
in
{
  options.mariano.folio.boot = {
    enable = lib.mkEnableOption "Interstellar's boot and disk-unlock screen (Plymouth, theme \"interstellar\")";

    followLook = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Follow the desktop's look (theme, mode, color and Lumen's sky)
        without a rebuild.
        The look the owner chooses is published by themeport's root bridge to
        ${appearance}; a root service prints it and writes it to
        ${lookFile}, and the default boot entry loads it after NixOS's
        initrd. Only these four checked values cross into the boot files.
        Off, the boot screen always shows the look set below.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.enum [
        "folio"
        "lumen"
      ];
      default = "folio";
      description = ''
        The look built into the initrd, shown until a look has been published
        (and whenever the published one is missing or damaged): Folio's
        plate and paper, or Lumen's nebula and page.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "light"
        "dark"
      ];
      default = "dark";
      description = ''
        Mode of the built-in look. Night is the default: it follows the
        firmware's black screen without a flash of paper, in a dark room or
        in the KVM's capture.
      '';
    };

    ink = lib.mkOption {
      type = color looks.inks;
      default = "azure";
      description = "Folio's ink for the built-in look: azure, cobalt, slate or #rrggbb (kept readable by looks.py).";
    };

    accent = lib.mkOption {
      type = color looks.accents;
      default = "blue";
      description = "Lumen's accent for the built-in look: one of Lumen's colors or #rrggbb (kept readable by looks.py).";
    };

    sky = lib.mkOption {
      type = lib.types.enum [
        "orbit"
        "prism"
        "glow"
        "haze"
      ];
      default = "orbit";
      description = "Lumen's sky for the built-in look, as shaders/lumen.frag draws it: orbit (a tilted ring of light with a soft trail), prism (ribbons of light through fluted glass), glow (one soft luminous shape) or haze (a full-bleed gradient).";
    };

    art = lib.mkOption {
      type = lib.types.str;
      default = "dore-nightfall";
      example = "summer-sicily";
      description = ''
        Folio plate shown beside the page, by catalog id
        (assets/azure-folio/catalog.json); the build fails on an unknown id.
        It stays fixed: a published look changes theme, mode, color and sky only.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = lib.toUpper (lib.substring 0 1 host) + lib.substring 1 (lib.stringLength host) host;
      defaultText = lib.literalExpression "capitalised networking.hostName";
      description = "Machine name on the page's tab and in its sentences.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Plymouth asks for the LUKS passphrase through systemd's password
        # agent in the systemd initrd. This module never changes the initrd
        # type.
        assertions = [
          {
            assertion = config.boot.initrd.systemd.enable;
            message = "mariano.folio.boot needs the systemd initrd (boot.initrd.systemd.enable); it does not switch initrd type itself.";
          }
        ];

        boot.plymouth = {
          enable = true;
          theme = "interstellar";
          themePackages = [ theme ];
          font = "${theme.fonts}/font-2.ttf";
          # The initrd has no GPU driver (amdgpu loads after the switch to the
          # real root), so the firmware framebuffer is the only display there.
          # Plymouth otherwise ignores it for DeviceTimeout (8 s) and the
          # passphrase prompt would wait on a blank screen.
          extraConfig = ''
            UseSimpledrm=1
          '';
        };

        # Inter and IBM Plex Mono in the initrd, for the strings Plymouth
        # renders at boot and for the console viewer behind Esc (the module
        # ships a single font file).
        boot.initrd.systemd.contents."/etc/plymouth/fonts".source = lib.mkForce theme.fonts;

        # Plymouth moves into the real root before the switch and redraws the
        # page when amdgpu replaces the firmware framebuffer, reading the
        # built-in look's images again from the initrd's copy of the theme.
        # Keep that store path in the system so a garbage collection cannot
        # take it away.
        system.extraDependencies = [ config.boot.initrd.systemd.contents."/etc/plymouth/themes".source ];

        # Quiet boot: the page instead of scrolling text. Errors still print,
        # and Esc shows everything that reached the console.
        boot.consoleLogLevel = lib.mkDefault 3;
        boot.kernelParams = [
          "quiet"
          "rd.udev.log_level=3"
          "udev.log_level=3"
          "rd.systemd.show_status=auto"
        ];
      }

      (lib.mkIf cfg.followLook {
        assertions = [
          {
            assertion = loader.systemd-boot.enable;
            message = "mariano.folio.boot.followLook adds the look to systemd-boot's entries; set followLook = false with another boot loader.";
          }
          {
            assertion = config.boot.initrd.systemd.shell.enable;
            message = "mariano.folio.boot.followLook checks the look with a shell script in the initrd (boot.initrd.systemd.shell.enable).";
          }
        ];

        boot.initrd.systemd.contents."/etc/plymouth/plymouthd.conf".source = lib.mkForce lookConf;
        boot.initrd.systemd.contents."/etc/plymouth/plymouthd.defaults".source = lib.mkForce builtinConf;
        environment.etc."plymouth/plymouthd.conf".source = lib.mkForce lookConf;
        environment.etc."plymouth/plymouthd.defaults".source = lib.mkForce builtinConf;

        # In the initrd: show the boot partition's look only if it is intact.
        boot.initrd.systemd.services.interstellar-boot-look-check = {
          description = "Check Interstellar's look on the boot partition";
          wantedBy = [ "plymouth-start.service" ];
          before = [ "plymouth-start.service" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "10s";
          };
          script = builtins.readFile ../../packages/plymouth-folio/boot-look-check.sh;
        };

        systemd.tmpfiles.rules = [ "d /run/interstellar 0755 root root -" ];

        # On the running system: print the published look and write it to the
        # boot partition. It reads only the root-owned file themeport's bridge
        # (azure-folio-greeter-state) reconstructs from the owner's selection,
        # and keeps four values from it, each checked again here.
        systemd.services.interstellar-boot-look = {
          description = "Write Interstellar's look to the boot partition for the disk-unlock screen";
          wantedBy = [ "multi-user.target" ];
          after = [
            "local-fs.target"
            "azure-folio-greeter-state.service"
          ];
          unitConfig.RequiresMountsFor = [ bootMount ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs [
              "${theme.publisher}/bin/interstellar-boot-look"
              "publish"
              "--input"
              appearance
              "--boot-file"
              lookFile
              "--state-dir"
              "/var/lib/interstellar-boot-look"
              "--runtime-dir"
              "/run/interstellar/themes"
            ];
            StateDirectory = "interstellar-boot-look";
            StateDirectoryMode = "0700";
            # Writable: the look's directory on the boot partition, its own
            # state, and the copy in /run for the shutdown page. Nothing else.
            ProtectSystem = "strict";
            ReadWritePaths = [
              "-${lookDir}"
              "-/run/interstellar"
            ];
            ProtectHome = true;
            PrivateTmp = true;
            PrivateNetwork = true;
            PrivateDevices = true;
            PrivateIPC = true;
            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            RestrictAddressFamilies = "none";
            IPAddressDeny = "any";
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged @resources"
            ];
            # A refused call fails instead of killing the print: numpy's
            # OpenBLAS asks for NUMA placement (mbind) as it loads, and does
            # without it. It needs no threads here either.
            SystemCallErrorNumber = "EPERM";
            Environment = [ "OPENBLAS_NUM_THREADS=1" ];
            UMask = "0077";
            Nice = 10;
            IOSchedulingClass = "idle";
            TimeoutStartSec = "5min";
          };
        };
        systemd.paths.interstellar-boot-look = {
          description = "Watch the published look for the disk-unlock screen";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = appearance;
            Unit = "interstellar-boot-look.service";
          };
        };

        boot.loader.systemd-boot.extraInstallCommands = lib.mkAfter ''
          ${installLook}
        '';
      })
    ]
  );
}
