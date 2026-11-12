# x86_64 programs on ackerman, route B (m5max-linux docs/x86.md): FEX on the host, in a process tree
# with 4K pages, as Aurora's distributions do it (nixos-aurora's userpages.nix and fex.nix,
# fedora-aurora's fex-userpages). No VM. The kernel does the 4K pages (CONFIG_ARM64_USER4K_EXPERIMENTAL,
# booted with `user4k=on`: hardware.nix), Aurora's FEX fork runs the x86 code, and the x86 build of the
# host's own Aurora Mesa drives the GPU directly through the `aurora` DRM node.
#
# No x86 root filesystem. FEX needs one for distribution binaries, whose loader and libraries are at
# /lib64 and /usr/lib; nixpkgs' x86_64 programs carry theirs: the ELF interpreter is
# /nix/store/...-glibc-.../ld-linux-x86-64.so.2 and every library is found by its /nix/store RPATH.
# With FEX's RootFS unset, FEX opens those paths on the host, where the x86_64 closures are. So the x86
# programs here are nixpkgs' x86_64-linux packages, built (or, for the unfree ones, repackaged) on
# bonhart and copied over: nothing downloaded at run time, nothing unpinned, and the same nixpkgs as
# everything else. A foreign x86 binary (a vendor tarball, an AppImage) still needs a rootfs: not
# provided yet.
#
# The Mac can't build x86_64 derivations (and mustn't try under FEX: x86_64-linux is deliberately not
# in nix's extra-platforms). bonhart builds them: `nix build
# .#nixosConfigurations.ackerman.config.system.build.ackermanX86`, then `nix copy` the result to the
# Mac before the rebuild there (m5max-linux builds/private/bundle-userspace.md).
#
# Off switches:
#   - ackerman.x86.enable = false: none of it (no user4k=on, FEX, binfmt, x86 Mesa or x86 apps);
#   - ackerman.x86.binfmt = false: no transparent launching (`x86-run PROGRAM` and the app launchers
#     still work);
#   - per launch: ACKERMAN_X86_GPU=0 (llvmpipe instead of the GPU), ACKERMAN_X86_NO_SANDBOX=1
#     (Chromium's sandbox off in Spotify and Slack, should it not start under FEX).
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.ackerman.x86;

  # x86_64-linux packages from the same nixpkgs. No overlays: none of this repository's touch these
  # packages, and leaving them out keeps the derivations the ones bonhart already has (Spotify and
  # Slack are bonhart's own).
  pkgsX86 = import pkgs.path {
    localSystem = "x86_64-linux";
    config.allowUnfree = true;
    overlays = [ ];
  };

  fex = pkgs.callPackage ./packages/x86/fex-aurora.nix { };
  userpages = pkgs.callPackage ./packages/x86/aurora-userpages.nix { };

  # The host's Mesa recipe and source, built for x86_64 (Aurora: the guest Mesa must be the host's
  # commit, since both speak the same kernel UAPI)
  mesaX86 = pkgsX86.callPackage ./packages/mesa-aurora.nix { };

  # FEX in a 4K-page process tree. Programs FEX starts inherit the 4K pages. As fedora-aurora's
  # fex-userpages, minus the page-size test: `userpages 4k` is harmless in a tree that already has
  # them, and says plainly when the kernel was booted without user4k=on. Arguments: the program,
  # then its arguments (binfmt below passes them in that form).
  fexUser4k = pkgs.writeShellScript "fex-user4k" ''
    exec ${userpages}/bin/userpages 4k ${fex}/bin/FEX "$@"
  '';

  # x86-run PROGRAM [ARGS...]: the way in from the aarch64 desktop
  x86Run = pkgs.writeShellScriptBin "x86-run" ''
    if [ $# -eq 0 ]; then
      echo "usage: x86-run PROGRAM [ARGS...]  (an x86_64 program, under FEX with 4K pages)" >&2
      exit 2
    fi
    # The session's aarch64 library and plugin paths would be loaded into the x86 process: clear
    # them (an x86 program's own wrapper sets its own)
    unset LD_LIBRARY_PATH LD_PRELOAD GTK_PATH GIO_EXTRA_MODULES GDK_PIXBUF_MODULE_FILE \
      GTK_IM_MODULE_FILE QT_PLUGIN_PATH QML2_IMPORT_PATH NIXPKGS_QT6_QML_IMPORT_PATH \
      GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_PATH LIBVA_DRIVERS_PATH VDPAU_DRIVER_PATH \
      ALSA_PLUGIN_DIR SPA_PLUGIN_DIR PIPEWIRE_MODULE_DIR __EGL_VENDOR_LIBRARY_DIRS \
      VK_ICD_FILENAMES VK_ADD_DRIVER_FILES
    # The x86_64 Aurora Mesa (/run/opengl-driver is the aarch64 one). GL follows the session's
    # choice (ackerman-gl): native, or zink over the x86 Asahi Vulkan driver.
    export LD_LIBRARY_PATH=${mesaX86}/lib
    export __EGL_VENDOR_LIBRARY_FILENAMES=${mesaX86}/share/glvnd/egl_vendor.d/50_mesa.json
    export LIBGL_DRIVERS_PATH=${mesaX86}/lib/dri
    export GBM_BACKENDS_PATH=${mesaX86}/lib/gbm
    export VK_DRIVER_FILES=${mesaX86}/share/vulkan/icd.d/asahi_icd.x86_64.json
    # ACKERMAN_X86_GPU=0: software GL (llvmpipe), no Vulkan
    if [ "''${ACKERMAN_X86_GPU:-1}" = 0 ]; then
      export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
      unset MESA_LOADER_DRIVER_OVERRIDE VK_DRIVER_FILES
    fi
    exec ${fexUser4k} "$@"
  '';

  # An x86_64 nixpkgs app as an aarch64 command and desktop entry of the same name
  x86App =
    {
      name,
      package,
      desktopFile,
      execFrom,
      execTo,
    }:
    pkgs.runCommand "${name}-x86" { } ''
      mkdir -p $out/bin $out/share/applications
      cat > $out/bin/${name} <<EOF
      #!${pkgs.runtimeShell}
      # ${name} is x86_64-only: ${package} under FEX (x86-run). ACKERMAN_X86_NO_SANDBOX=1 turns
      # Chromium's sandbox off, should it not start under FEX.
      exec ${x86Run}/bin/x86-run ${package}/bin/${name} \''${ACKERMAN_X86_NO_SANDBOX:+--no-sandbox} "\$@"
      EOF
      chmod +x $out/bin/${name}
      cp -r ${package}/share/icons $out/share/icons
      sed -e 's|^Exec=${execFrom}|Exec=${execTo}|' -e '/^TryExec=/d' \
        ${package}/share/applications/${desktopFile} > $out/share/applications/${desktopFile}
      grep -q '^Exec=${execTo}' $out/share/applications/${desktopFile}
    '';

  apps = {
    spotify = x86App {
      name = "spotify";
      package = pkgsX86.spotify;
      desktopFile = "spotify.desktop";
      execFrom = "spotify ";
      execTo = "${placeholder "out"}/bin/spotify ";
    };
    slack = x86App {
      name = "slack";
      package = pkgsX86.slack;
      desktopFile = "slack.desktop";
      execFrom = "${pkgsX86.slack}/bin/slack ";
      execTo = "${placeholder "out"}/bin/slack ";
    };
  };
in
{
  options.ackerman.x86 = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        x86_64 programs through FEX in 4K-page process trees (route B): user4k=on on the kernel
        command line, Aurora's FEX and userpages, the x86_64 Aurora Mesa, x86-run, and Spotify and
        Slack as launchers. False removes all of it.
      '';
    };
    binfmt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run x86_64 ELF files transparently (binfmt_misc hands them to FEX in a 4K tree). Without
        it, x86 programs start only through x86-run and the launchers.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = mesaX86.src.outPath == config.hardware.graphics.package.src.outPath;
        message = "ackerman.x86: the x86_64 Mesa must be built from the host Mesa's source";
      }
    ];

    environment.systemPackages = [
      fex
      userpages
      x86Run
    ]
    ++ lib.attrValues apps;

    # binfmt_misc: x86_64 ELF executables go to FEX in a 4K tree. Not preserve-argv0, open-binary
    # or fix-binary: the interpreter is a script that starts FEX again in a new 4K address space,
    # and that exec loses what those flags hand the first one (AT_FLAGS, AT_EXECFD), so FEX gets
    # plain arguments (program, then its arguments; argv[0] becomes the program's path). Only
    # x86_64 is registered: FEX then also runs the x86 programs a guest starts itself (it checks for
    # both FEX-x86 and FEX-x86_64), which keeps their argv[0].
    boot.binfmt.registrations = lib.mkIf cfg.binfmt {
      "FEX-x86_64" = {
        inherit (utils.binfmtMagics.x86_64-linux) magicOrExtension mask;
        interpreter = "${fexUser4k}";
        recognitionType = "magic";
        offset = 0;
        preserveArgvZero = false;
        openBinary = false;
        matchCredentials = false;
        fixBinary = false;
        wrapInterpreterInShell = false;
      };
    };

    # On bonhart: `nix build .#nixosConfigurations.ackerman.config.system.build.ackermanX86`, an
    # x86_64 derivation whose closure is every x86_64 path this system needs; then nix copy it to
    # the Mac
    system.build.ackermanX86 = pkgsX86.linkFarm "ackerman-x86" {
      inherit (pkgsX86) spotify slack;
      mesa = mesaX86;
    };
  };
}
