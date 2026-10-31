{
  imports = [
    ./common.nix
    # The guided installer's encrypted LVM layout with hibernation swap. It is
    # tracked, unlike other machines' installer-written storage.nix, because
    # Update All builds only committed files; a reinstall writes the same
    # content here (storage-encrypted.nix), which bonhart-install uses too.
    ./storage.nix
  ];
}
