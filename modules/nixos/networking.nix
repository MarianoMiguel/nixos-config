{ pkgs, ... }:

{
  networking.networkmanager.enable = true;

  services.tailscale = {
    enable = true;
    interfaceName = "ts0";
    useRoutingFeatures = "both";
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
