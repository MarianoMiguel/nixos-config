{ pkgs, ... }:

{
  # Bonhart's Goodix reader is supported by the upstream libfprint stack.
  # Keep biometric authentication machine-specific: the desktop profile is
  # shared with hosts that do not have a fingerprint reader.
  services.fprintd.enable = true;

  # DMS handles its lock screen itself, while greetd and the normal system
  # authentication surfaces use PAM. DMS's fingerprint settings are enforced
  # in home.nix so login, lock, polkit and sudo all expose the same capability.
  security.pam.services = {
    greetd.fprintAuth = true;
    login.fprintAuth = true;
    polkit-1.fprintAuth = true;
    sudo.fprintAuth = true;
  };

  environment.systemPackages = [ pkgs.fprintd ];
}
