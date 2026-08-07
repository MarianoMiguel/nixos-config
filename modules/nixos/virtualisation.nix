{ pkgs, config, ... }:

{
  virtualisation.docker = {
    enable = true;
    # docker.socket remains enabled, so the daemon starts automatically on the
    # first Docker command without spending memory and I/O on every boot.
    enableOnBoot = false;
    package = pkgs.docker_29;
  };
}
