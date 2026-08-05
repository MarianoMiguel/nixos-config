{ pkgs, ... }:

{
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

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

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      KbdInteractiveAuthentication = true;
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=mariano" ];
    interfaceName = "ts0";
    useRoutingFeatures = "both";
  };

  systemd.user.services.tailscale-systray = {
    description = "Tailscale system tray";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscale systray";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  networking.firewall.trustedInterfaces = [ "ts0" ];

  services.opensnitch = {
    enable = true;
    settings.ProcMonitorMethod = "proc";
  };

  environment.systemPackages = with pkgs; [
    tailscale
    opensnitch-ui
    protonvpn-gui
  ];
}
