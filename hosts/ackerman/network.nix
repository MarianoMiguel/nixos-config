# ackerman's network: Wi-Fi (the N1) through NetworkManager on iwd, the USB tether to bonhart
# (usb0 10.55.0.2, gateway 10.55.0.1) through systemd-networkd, and sshd with keys only.
{ ... }:

let
  keys = import ./files/keys/authorized-keys.nix;
in
{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.wireless.iwd = {
    enable = true;
    settings.General.EnableNetworkConfiguration = false;
  };
  # Wi-Fi through NetworkManager (2026-11-08, Mariano's call): DMS's network panel speaks NetworkManager
  # only. iwd stays the Wi-Fi daemon (NetworkManager's iwd backend) and keeps the saved networks;
  # NetworkManager does wlan0's DHCP and hands its DNS to resolved. The tether is the way back in
  # when anything else breaks: NetworkManager never touches usb0, which stays networkd's.
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
    dns = "systemd-resolved";
    unmanaged = [ "interface-name:usb0" ];
  };
  # The Mac has no modem
  networking.modemmanager.enable = false;
  systemd.network = {
    # Online when any link is: the tether is up from the initrd on, and the Wi-Fi may be late or
    # absent (the first boot had no wlan0, and wait-online held every boot and switch for 120 s).
    # wlan0 is NetworkManager's (NetworkManager-wait-online), so networkd waits for usb0 only
    wait-online.anyInterface = true;
    enable = true;
    # The tether stays the way to bonhart (10.55.0.0/24) and is the internet route only when Wi-Fi
    # is down: its default route sits behind wlan0's (NetworkManager's, metric 600)
    networks."10-usb0" = {
      matchConfig.Name = "usb0";
      address = [ "10.55.0.2/24" ];
      routes = [
        {
          Gateway = "10.55.0.1";
          Metric = 2048;
        }
      ];
      dns = [ "1.1.1.1" ];
      # Counts for network-online (wait-online.anyInterface): either the tether or the Wi-Fi will do
      linkConfig.RequiredForOnline = "routable";
    };
  };
  services.resolved.enable = true;

  # More parallel downloads from cache.nixos.org (ackerman builds itself)
  nix.settings = {
    http-connections = 64;
    max-substitution-jobs = 32;
  };

  networking.firewall.trustedInterfaces = [ "usb0" ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = keys.bonhart ++ keys.macbook;
}
