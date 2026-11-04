{ rex, ... }:

# Rex as a remote host for the Rex apps on the Mac and other devices.
#
# The login server runs as root, asks the host's tailscaled who each caller
# is, and runs a Rex server as the account that caller maps to, inside a PAM
# login session. Tailscale Serve carries it to the tailnet over HTTPS on port
# 7297 (the module's rex-tailscale-serve unit), so nothing listens on an
# ordinary interface and the firewall stays as it is. Only the tailnet's own
# login reaches mariano; every other caller is refused.
#
# Clients add the host by name alone, bonhart.taile97d70.ts.net; the Rex CLI
# tries ports 443 and 7297. See docs/remote-workstation.md.
let
  owner = "tailscale:office@marianomiguel.com";
in
{
  imports = [ rex.nixosModules.default ];

  services.rex.loginServer = {
    enable = true;
    accounts.mariano.principals = [ owner ];
    defaults.${owner} = "mariano";
    tailscaleServe.enable = true;
  };
}
