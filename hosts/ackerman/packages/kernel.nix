# ackerman's kernel, wrapped in the shape NixOS expects of a kernel package.
#
# It is not built here: it carries this unit's GPU voltages, so it is built on bonhart from the
# J716C bring-up tree (MarianoMiguel/m5max-linux, tools/build-kernel-gpu.sh with
# tools/nixos/ackerman-kernel.config) and arrives through the private input, as
# nixos/kernel/{Image.gz, t6050-j716c.dtb, config, modules/, release}. LUKS, dm-crypt and btrfs are
# built in, so the initrd needs no modules.
{
  lib,
  stdenvNoCC,
  writeText,
  kmod,
  src,
  # NixOS's boot.kernelPackages passes these through kernel.override; a prebuilt kernel takes no
  # patches (build them into the tree on bonhart instead)
  kernelPatches ? [ ],
  features ? { },
  randstructSeed ? "",
}:

assert lib.assertMsg (kernelPatches == [ ]) "linux-ackerman is prebuilt: boot.kernelPatches can't apply";

let
  release = lib.removeSuffix "\n" (builtins.readFile (src + "/release"));
  version = builtins.head (lib.splitString "-" release);

  # The .config as an attribute set, read without import-from-derivation (the file is already in
  # the store), in the form linuxManualConfig gives: CONFIG_X = "y" | "m" | "<value>".
  parsed = builtins.listToAttrs (
    lib.concatMap (
      line:
      let
        m = builtins.match "(CONFIG_[A-Za-z0-9_]+)=\"?([^\"]*)\"?" line;
      in
      lib.optional (m != null) {
        name = builtins.elemAt m 0;
        value = builtins.elemAt m 1;
      }
    ) (lib.splitString "\n" (builtins.readFile (src + "/config")))
  );
  config =
    let
      attr = a: "CONFIG_" + a;
      getValue = a: parsed.${attr a} or null;
    in
    parsed
    // rec {
      isSet = a: parsed ? ${attr a};
      inherit getValue;
      isYes = a: getValue a == "y";
      isNo = a: getValue a == "n";
      isModule = a: getValue a == "m";
      isEnabled = a: isModule a || isYes a;
      isDisabled = a: !(isSet a) || isNo a;
    };
in
stdenvNoCC.mkDerivation {
  pname = "linux-ackerman";
  inherit version src;

  nativeBuildInputs = [ kmod ];
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 Image.gz $out/Image.gz
    # The self-decompressing EFI image, for the boot menu's systemd-boot entries (CONFIG_EFI_ZBOOT,
    # from the bundle kernel on); m1n1's payloads take Image.gz
    if [ -e vmlinuz.efi ]; then install -Dm644 vmlinuz.efi $out/vmlinuz.efi; fi
    install -Dm644 t6050-j716c.dtb $out/dtbs/apple/t6050-j716c.dtb
    # The PMP-off device tree, for a payload variant: ackerman-payload build ... --dtb
    # /run/current-system/dtbs/apple/t6050-j716c-nopmp.dtb (from the bundle kernel on)
    if [ -e t6050-j716c-nopmp.dtb ]; then
      install -Dm644 t6050-j716c-nopmp.dtb $out/dtbs/apple/t6050-j716c-nopmp.dtb
    fi
    install -Dm644 config $out/config
    install -Dm644 recipe.txt $out/recipe.txt
    mkdir -p $out/lib/modules
    cp -r modules/${release} $out/lib/modules/${release}
    chmod -R u+w $out/lib/modules
    depmod -b $out -a ${release}
    runHook postInstall
  '';

  passthru = {
    inherit config release;
    # NixOS reads it (the ASLR entropy sysctl); a copy, not the whole private input
    configfile = writeText "linux-ackerman-${release}.config" (builtins.readFile (src + "/config"));
    modDirVersion = release;
    baseVersion = version;
    inherit features;
    kernelOlder = lib.versionOlder version;
    kernelAtLeast = lib.versionAtLeast version;
    isZen = false;
    isHardened = false;
    isLibre = false;
    isXen = false;
  };

  meta = {
    description = "Linux for ackerman (MacBook Pro 16-inch M5 Max, J716C), built on bonhart";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Only;
  };
}
