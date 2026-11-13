# What bonhart has and ackerman lacked after the core install (2026-11-08), where nixpkgs builds
# it for aarch64 and cache.nixos.org has it: GNOME's standalone apps (they run on niri), the
# file-system tools, and the X11 helpers for xwayland-satellite's clients. parity.nix adds the rest
# of that kind (2026-11-09: Zed, Krita, Codex, Proton VPN, printing, Avahi, ...).
# Left out on purpose: the GNOME session and its X server, bonhart's own hardware (fingerprint,
# Thunderbolt, battery limit, the FIDO bridge, the tablet), and apps with no aarch64 package yet:
# Steam, DaVinci, Figma and Fluent Reader have no arm64 Linux build; Spotify runs as an x86_64
# program through FEX (x86.nix, m5max-linux docs/x86.md), Slack as a Chrome app (apps-arm64.nix); Beeper, Paper, herdr, OnlyOffice and
# CodexBar come from their arm64 builds (apps-arm64.nix, packages/beeper.nix); Obsidian, Codex
# Desktop and LibrePods build on the Mac (app-sets.nix, apps-arm64.nix).
{ pkgs, rex, ... }:

{
  environment.systemPackages = with pkgs; [
    # The Rex CLI only (rex.nix's login server needs Tailscale, which ackerman doesn't run): a
    # Claude Code session in Rex, driven from bonhart over SSH (2026-11-09)
    rex.packages.${pkgs.stdenv.hostPlatform.system}.default
    # GNOME's apps
    baobab
    decibels
    epiphany
    evolution
    gnome-calculator
    gnome-calendar
    gnome-characters
    gnome-clocks
    gnome-connections
    gnome-contacts
    gnome-disk-utility
    gnome-font-viewer
    gnome-logs
    gnome-maps
    gnome-music
    gnome-system-monitor
    gnome-text-editor
    gnome-weather
    loupe
    papers
    seahorse
    showtime
    # bonhart's file manager, archive tool and text editor
    nautilus
    file-roller
    kdePackages.kate
    # File systems and Bluetooth
    e2fsprogs
    exfatprogs
    ntfs3g
    bluez-tools
    xdg-user-dirs
    # X11 helpers (xwayland-satellite)
    xinput
    xprop
    xrandr
    # Spotify in a terminal (Spotify Connect, Premium for playback): Spotify has no aarch64 Linux
    # client; the official one runs through FEX (x86.nix)
    spotify-player
  ];

  # Default apps as on bonhart (its GNOME session's, 2026-11-08): the browser and the PDF viewer come
  # from apps.nix, the terminal from xdg-terminal-exec (Ghostty); folders and zips open in Files,
  # calendars in Calendar, plain text in Kate. bonhart sets no mail handler. Its images, videos and
  # music have no default and fall back to Brave and HandBrake; here they open in GNOME's viewers.
  xdg.mime.defaultApplications =
    let
      each = desktop: types: builtins.listToAttrs (map (t: { name = t; value = desktop; }) types);
    in
    each "org.gnome.Nautilus.desktop" [ "inode/directory" "application/zip" ]
    // each "org.gnome.Calendar.desktop" [ "text/calendar" ]
    // each "org.kde.kate.desktop" [ "text/plain" ]
    // each "org.gnome.Loupe.desktop" [ "image/png" "image/jpeg" "image/webp" "image/gif" "image/avif" "image/heif" ]
    // each "org.gnome.Showtime.desktop" [ "video/mp4" "video/webm" "video/x-matroska" "video/quicktime" ]
    // each "org.gnome.Decibels.desktop" [ "audio/mpeg" "audio/flac" "audio/ogg" "audio/x-wav" "audio/mp4" ];

  # Calendar, Contacts and Evolution keep their data in evolution-data-server; Disks needs udisks2
  services.gnome.evolution-data-server.enable = true;
  services.udisks2.enable = true;
}
