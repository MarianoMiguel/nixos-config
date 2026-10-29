{
  config,
  lib,
  pkgs,
  ...
}:

# Folio's boot and disk-unlock screen: Plymouth with the "folio" theme
# (packages/plymouth-folio) instead of the bare console LUKS prompt.
#
# Off by default; the owner turns it on and tries it in person
# (docs/folio-boot.md). With it off, the system is built exactly as before.
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
  theme = pkgs.callPackage ../../packages/plymouth-folio {
    machineName = cfg.name;
    folioMode = cfg.mode;
    folioInk = cfg.ink;
    folioArt = cfg.art;
  };
in
{
  options.mariano.folio.boot = {
    enable = lib.mkEnableOption "Folio's boot and disk-unlock screen (Plymouth, theme \"folio\")";

    mode = lib.mkOption {
      type = lib.types.enum [
        "light"
        "dark"
      ];
      default = "dark";
      description = ''
        Paper for the boot screen. The boot happens before any session, so
        it cannot follow the desktop's light/dark selection (that lives in
        the encrypted home); it is fixed when the system is built. Night is
        the default: it follows the firmware's black screen without a flash
        of paper, in a dark room or in the KVM's capture.
      '';
    };

    ink = lib.mkOption {
      type = lib.types.enum [
        "azure"
        "cobalt"
        "slate"
      ];
      default = "azure";
      description = "Folio ink for the plate, the name tab and the typed dots.";
    };

    art = lib.mkOption {
      type = lib.types.str;
      default = "dore-nightfall";
      example = "summer-sicily";
      description = ''
        Folio plate shown beside the page, by catalog id
        (assets/azure-folio/catalog.json); the build fails on an unknown id.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = lib.toUpper (lib.substring 0 1 host) + lib.substring 1 (lib.stringLength host) host;
      defaultText = lib.literalExpression "capitalised networking.hostName";
      description = "Machine name on the page's tab and in \"Unlock <name>'s disk\".";
    };
  };

  config = lib.mkIf cfg.enable {
    # Plymouth asks for the LUKS passphrase through systemd's password agent
    # in the systemd initrd. This module never changes the initrd type.
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "mariano.folio.boot needs the systemd initrd (boot.initrd.systemd.enable); it does not switch initrd type itself.";
      }
    ];

    boot.plymouth = {
      enable = true;
      theme = "folio";
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

    # Inter and IBM Plex Mono in the initrd, for the strings Plymouth renders
    # at boot and for the console viewer behind Esc (the module ships a
    # single font file).
    boot.initrd.systemd.contents."/etc/plymouth/fonts".source = lib.mkForce theme.fonts;

    # Quiet boot: the page instead of scrolling text. Errors still print,
    # and Esc shows everything that reached the console.
    boot.consoleLogLevel = lib.mkDefault 3;
    boot.kernelParams = [
      "quiet"
      "rd.udev.log_level=3"
      "udev.log_level=3"
      "rd.systemd.show_status=auto"
    ];
  };
}
