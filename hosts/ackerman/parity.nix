# What bonhart has and ackerman lacked, where it is built for aarch64 and on cache.nixos.org
# (Mariano: "everything we have here should be on ackerman"; the audit of 2026-11-09 is m5max-linux
# builds/private/parity-bonhart-ackerman.md). Not here: GNOME's own desktop and bonhart's hardware;
# the apps that build from source or need repackaging (app-sets.nix, packages/); Tailscale and Rex
# (tailscale.nix); OpenSnitch, Update All and Plymouth (Mariano's call).
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Cached for aarch64 now, so out from behind bigApps here
    zed-editor
    krita
    codex
    proton-vpn
    # GNOME's apps bonhart has and apps-extra.nix didn't carry
    snapshot
    simple-scan
    yelp
    gnome-console
    tecla
    gnome-software
    # Printing's settings, and the image and video thumbnails in Files
    system-config-printer
    glycin-loaders
    gst-thumbnailers
  ];

  # As bonhart (networking.nix): mDNS, its hostname published
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # As bonhart (common.nix), with brlaser alone: Brother's own HL-1210W driver is i686 binaries
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };
  programs.system-config-printer.enable = true;
  users.users.mariano.extraGroups = [
    "lp"
    "scanner"
  ];

  # Files: the trash, phones (MTP) and network places (gvfs), TLS for GIO apps, the space-bar preview
  # (Sushi), search and indexing (localsearch over tinysparql), and online accounts for Calendar and
  # Contacts
  services.gvfs.enable = true;
  services.gnome.glib-networking.enable = true;
  services.gnome.sushi.enable = true;
  services.gnome.localsearch.enable = true;
  services.gnome.tinysparql.enable = true;
  services.gnome.gnome-online-accounts.enable = true;

  # As bonhart (desktop.nix): headsets' and AirPods' battery levels
  hardware.bluetooth = {
    powerOnBoot = true;
    settings.General.Experimental = true;
  };

  # As bonhart (common.nix): Argentine formats, English language
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_AR.UTF-8";
    LC_IDENTIFICATION = "es_AR.UTF-8";
    LC_MEASUREMENT = "es_AR.UTF-8";
    LC_MONETARY = "es_AR.UTF-8";
    LC_NAME = "es_AR.UTF-8";
    LC_NUMERIC = "es_AR.UTF-8";
    LC_PAPER = "es_AR.UTF-8";
    LC_TELEPHONE = "es_AR.UTF-8";
    LC_TIME = "es_AR.UTF-8";
  };

  # As bonhart (desktop.nix): Qt apps read Themeport's kdeglobals through KDE's platform theme
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };
}
