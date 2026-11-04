{ pkgs, ... }:

let
  # PAM is serial: applications that use one context for both fingerprint and
  # password authentication cannot reach pam_unix until pam_fprintd returns.
  # One try and a short timeout, so a missed scan falls through quickly
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

  # The login screen (greetd, whose greeter offers the reader because
  # login-screen.nix sets greeterEnableFprint), console login and sudo all
  # take a finger. Admin prompts (polkit) take the root password only
  # (users.nix makes root the only administrator identity), so polkit-1 has
  # no fingerprint.
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
    polkit-1.fprintAuth = false;
    sudo = {
      fprintAuth = true;
      rules.auth.fprintd.settings = fingerprintFallback;
    };
  };

  environment.systemPackages = [ pkgs.fprintd ];
}
