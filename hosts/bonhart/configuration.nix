{ lib, ... }:

let
  installedStorage = builtins.pathExists ./storage.nix;
in
{
  imports = [
    ./common.nix
  ]
  ++ lib.optional installedStorage ./storage.nix
  ++ lib.optional (!installedStorage) ./storage-legacy.nix;
}
