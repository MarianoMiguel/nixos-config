{ lib, pkgs, ... }:

{
  boot.kernelModules = [ "uhid" ];
  # Bonhart is an unattended, mains-powered agent host. Keep battery
  # hibernation as an outage safeguard; a closed lid on AC must stay online.
  services.logind.settings.Login.HandleLidSwitchExternalPower = lib.mkForce "ignore";
  home-manager.users.mariano.dconf.settings."org/gnome/settings-daemon/plugins/power".lid-close-ac-action =
    lib.mkForce "nothing";

  environment.systemPackages = [
    (pkgs.callPackage ../../packages/fido-bridge.nix { })
    (pkgs.writeShellScriptBin "agent-account" ''
      exec ${pkgs.python3}/bin/python3 ${../../scripts/agent-account.py} "$@"
    '')
    pkgs.rsync
  ];
}
