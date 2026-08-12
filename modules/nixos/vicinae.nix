{ pkgs, ... }:

let
  gnomeWindowManagementExtension =
    pkgs.callPackage ../../packages/gnome-shell-extension-vicinae-window-management.nix { };
  gnomeWindowAction = pkgs.writeShellScript "vicinae-gnome-window-action" ''
    exec ${pkgs.glib}/bin/gdbus call \
      --session \
      --dest org.gnome.Shell \
      --object-path /org/gnome/Shell/Extensions/VicinaeWindowManagement \
      --method org.gnome.Shell.Extensions.VicinaeWindowManagement.Execute \
      "$1"
  '';
in
{
  # gdbus is the deliberately small bridge between the Vicinae command
  # extension and the GNOME Shell extension. Keep it in the stable system PATH
  # because Vicinae commands run from a user service rather than an interactive
  # shell.
  environment.systemPackages = [
    pkgs.glib
    pkgs.vicinae
  ];

  home-manager.users.mariano = { config, lib, ... }: {
    programs.vicinae = {
      enable = true;
      systemd = {
        enable = true;
        autoStart = true;
      };
      extensions = [
        (config.lib.vicinae.mkExtension {
          name = "gnome-window-management";
          src = ../../extensions/vicinae-window-management;
        })
      ];
    };

    # The official bridge gives Vicinae GNOME-native clipboard/window access.
    # The local companion implements the high-level layouts against GNOME's
    # exact per-monitor work area and remembers the app focused before Vicinae.
    programs.gnome-shell = {
      enable = true;
      extensions = [
        { package = pkgs.gnomeExtensions.dash-to-dock; }
        { package = pkgs.gnomeExtensions.vicinae; }
        { package = gnomeWindowManagementExtension; }
      ];
    };

    dconf.settings = {
      "org/gnome/desktop/wm/keybindings" = {
        activate-window-menu = lib.hm.gvariant.mkEmptyArray lib.hm.gvariant.type.string;
      };

      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-center/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-almost-maximize/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-hide-others/"
        ];
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae" = {
        binding = "<Alt>space";
        command = "${pkgs.vicinae}/bin/vicinae toggle";
        name = "Toggle Vicinae";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-center" = {
        binding = "<Alt>bracketleft";
        command = "${gnomeWindowAction} center";
        name = "Center Window";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-almost-maximize" = {
        binding = "<Alt>bracketright";
        command = "${gnomeWindowAction} almost-maximize";
        name = "Almost Maximize Window";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-hide-others" = {
        binding = "<Alt>apostrophe";
        command = "${gnomeWindowAction} hide-others";
        name = "Hide Other Applications";
      };
    };
  };
}
