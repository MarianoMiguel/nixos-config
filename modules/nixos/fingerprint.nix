{ pkgs, ... }:

let
  # PAM is serial: applications that use one context for both fingerprint and
  # password authentication cannot reach pam_unix until pam_fprintd returns.
  # Match DMS's managed greeter policy so a missed scan falls through quickly
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

  # DMS handles its lock screen itself, while greetd and the normal system
  # authentication surfaces use PAM. DMS's fingerprint settings are enforced
  # in home.nix so login, lock, polkit and sudo all expose the same capability.
  security.pam.services = {
    # PAM rule overrides are an experimental NixOS interface and need review
    # when the nixpkgs PAM module changes. Relative ordering remains owned by
    # nixpkgs; only pam_fprintd's documented arguments are overridden here.
    greetd = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
    login = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
    polkit-1 = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
    sudo = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
    swaylock.rules.auth.fprintd.settings = fingerprintFallback;

    # DMS deliberately runs password and fingerprint authentication in two
    # parallel PAM contexts. Its password context prefers /etc/pam.d/dankshell
    # when present; without this service it falls back to `login`, whose first
    # module is pam_fprintd, so a typed password is stuck behind the fingerprint
    # prompt and ends as an authentication error. Keep this context password-
    # only while DMS's separate `fprint` context handles the enrolled finger.
    dankshell = {
      allowNullPassword = false;
      fprintAuth = false;
    };
  };

  environment.systemPackages = [ pkgs.fprintd ];
}
