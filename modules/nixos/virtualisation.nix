{ pkgs, config, ... }:

{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    package = pkgs.docker_29;
  };
}
