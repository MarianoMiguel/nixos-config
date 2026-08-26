{ pkgs, ... }:

let
  # PAM is serial: applications that use one context for both fingerprint and
  # password authentication cannot reach pam_unix until pam_fprintd returns.
  # Keep a missed scan short on system authentication surfaces
  # instead of leaving password authentication spinning for the module's
  # default timeout.
  fingerprintFallback = {
    "max-tries" = 1;
    timeout = 5;
  };
in
{
  # Bonhart's Goodix reader is supported by the upstream libfprint stack.
  # Keep biometric authentication machine-specific: the desktop profile is
  # shared with hosts that do not have a fingerprint reader.
  services.fprintd.enable = true;

  # GDM runs its password and fingerprint PAM conversations independently, so
  # login and GNOME unlock retain both methods without a serial fallback delay.
  security.pam.services = {
    # PAM rule overrides are an experimental NixOS interface and need review
    # when the nixpkgs PAM module changes. Relative ordering remains owned by
    # nixpkgs; only pam_fprintd's documented arguments are overridden here.
    polkit-1 = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
    sudo = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
  };

  environment.systemPackages = [ pkgs.fprintd ];
}
