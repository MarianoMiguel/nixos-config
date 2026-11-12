# Tailscale on ackerman (Mariano, 2026-11-09: "it's important"), as bonhart has it
# (modules/nixos/networking.nix's part), next to NetworkManager; and Rex's login server through
# Tailscale Serve (modules/nixos/rex.nix, as on bonhart: only office@marianomiguel.com, as mariano),
# so his Rex apps reach ackerman the way they reach bonhart, at https://ackerman.<tailnet>:7297.
# The tailnet name is the hostname. The login is Mariano's (`tailscale up` prints the URL). The USB
# tether (usb0, networkd) stays as it is. See docs/remote-workstation.md.
{ ... }:

{
  imports = [ ../../modules/nixos/rex.nix ];

  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=mariano" ];
    interfaceName = "ts0";
    # A plain client. "client" would turn on loose reverse-path filtering, which needs the
    # kernel's iptables rpfilter match; ackerman's kernel has only nftables' fib match, so NixOS
    # leaves reverse-path checks off here (an assertion stops the build otherwise). Exit nodes and
    # subnet routes, which need it, aren't used from a laptop.
    useRoutingFeatures = "none";
  };

  # SSH and Rex over the tailnet; nothing else opens
  networking.firewall.trustedInterfaces = [ "ts0" ];

  # tailscaled owns its interface; NetworkManager leaves it alone (as it does usb0)
  networking.networkmanager.unmanaged = [ "interface-name:ts0" ];
}
