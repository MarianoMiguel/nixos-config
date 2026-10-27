{
  pkgsPond,
  src,
}:

# Pond's launcher (pond-launcher on Arch) is a Vicinae fork based on 0.29.0.
# nixos-26.05 only carries Vicinae 0.20, so build the fork with the
# nixos-unstable recipe that already packages 0.29 and its dependencies;
# only the source and the npm lock hashes differ.
pkgsPond.vicinae.overrideAttrs (
  finalAttrs: previousAttrs: {
    pname = "pond-vicinae";
    version = "0.29.0-pond-${builtins.substring 0 7 (src.rev or "dirty")}";
    inherit src;

    apiDeps = pkgsPond.fetchNpmDeps {
      src = "${src}/src/typescript/api";
      hash = "sha256-4FEaBDJK9abcgz+vptuL4wQ8zhp+wpLbbR4Y79BVhEg=";
    };

    extensionManagerDeps = pkgsPond.fetchNpmDeps {
      src = "${src}/src/typescript/extension-manager";
      hash = "sha256-pEgqFgvdz7Bcc+LznCI+KlD1XEfUuWFWjS24MJ7sx3k=";
    };

    # Pond already ships telemetry disabled, so the recipe's opt-in rewrite
    # would fail its replace-fail check.
    postPatch = ''
      local postPatchHooks=()
      source ${pkgsPond.npmHooks.npmConfigHook}/nix-support/setup-hook
      npmRoot=src/typescript/api npmDeps=${finalAttrs.apiDeps} npmConfigHook
      npmRoot=src/typescript/extension-manager npmDeps=${finalAttrs.extensionManagerDeps} npmConfigHook
    '';

    meta = previousAttrs.meta // {
      description = "Pond's fork of the Vicinae launcher";
      homepage = "https://github.com/bflycomputer/vicinae";
    };
  }
)
