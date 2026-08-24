{ pkgs, ... }:

{
  networking.networkmanager.enable = true;

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
    # NixOS user services receive a minimal PATH. Tailscale's tray uses the
    # session BROWSER setting first and xdg-open as its portable fallback, so
    # both must be resolvable when it opens login and administration links.
    path = [
      pkgs.google-chrome
      pkgs.xdg-utils
    ];
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
    proton-vpn
  ];
}
