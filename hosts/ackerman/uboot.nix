# uboot.nix: systemd-boot entries for ackerman's U-Boot payload (boot.bin.uboot). OFF by default.
#
# The boot menu (m5max-linux builds/private/uboot/README.md): the A/B stage-1 boots boot.bin.uboot
# (m1n1, then Aurora's U-Boot with three J716C patches), which starts systemd-boot from the ESP. It
# is never boot.bin by itself: it is copied in for an attended test. With
# `ackerman.uboot.enable = false` (the default) it changes nothing: the system's drvPath stays the
# same.
#
# What it does when enabled, after every switch/boot, in boot-m1n1.nix's boot-loader hook:
#   1. `ackerman-payload install TOPLEVEL` runs first, as always (boot.bin, the self-test,
#      boot.bin.prev rules: all unchanged, and a failure there still fails the switch);
#   2. then `ackerman-uboot-entries install TOPLEVEL`, which writes, on the ESP:
#        EFI/ackerman/systemd-bootaa64.efi       systemd-boot (config.systemd.package), which
#                                                boot.bin.uboot's U-Boot starts
#        EFI/ackerman/<hash>-vmlinuz.efi         each kernel's self-decompressing EFI image, when
#                                                the kernel package has one (CONFIG_EFI_ZBOOT)
#        EFI/ackerman/<hash>-Image.efi           otherwise the kernel, decompressed (systemd-boot
#                                                260 loads PE images only; it can't take Image.gz)
#        EFI/ackerman/<hash>-<secrets>-initrd.xz each initrd with its secrets, as xz (CRC32), which
#                                                the kernel unpacks itself
#        loader/entries/ackerman-uboot-genN.conf one entry per generation, newest first
#        loader/loader.conf                      only if absent or written by this tool
#      and, only with `payload.uboot` set, m1n1/boot.bin.uboot (never boot.bin).
#      It keeps N x boot.bin + 20 MiB + reserveMiB free (what the next payload install needs plus a
#      margin: N is 1 while m1n1/prev.pinned exists, since an install then writes boot.bin only,
#      else 2, as ackerman-payload's own check), drops older generations to stay there, and never
#      fails the switch.
#
# The entries carry no m5.selftest=1: a U-Boot boot is attended, and the self-test must not
# promote or revert it. They carry ackerman.boot=uboot, so /proc/cmdline shows how it came up.
# The devicetree is the one in boot.bin.uboot (m1n1 prepares it; U-Boot passes it on): entries
# have no `devicetree` line, which would replace m1n1's tree with a raw one.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ackerman.uboot;
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  sdboot = "${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
  # Copies, so the system's closure holds these files and not the whole private input they may
  # come from (as boot-m1n1.nix's m1n1)
  copy =
    name: p:
    if p == null then
      null
    else
      pkgs.runCommand name { } ''
        install -Dm644 ${p} $out
      '';
  ubootFile = copy "u-boot-nodtb.bin.gz" cfg.payload.uboot;
  m1n1File = copy "m1n1-stage2-uboot.bin" cfg.payload.m1n1;

  # Python: no two adjacent single quotes and no dollar-brace in this text (Nix string rules).
  entries = pkgs.writeScriptBin "ackerman-uboot-entries" ''
    #!${pkgs.python3}/bin/python3 -I
    """ackerman-uboot-entries - systemd-boot entries on ackerman's ESP for the U-Boot payload.

      ackerman-uboot-entries install TOPLEVEL   entries for TOPLEVEL (the default) and older ones
      ackerman-uboot-entries default N          make generation N the default (loader.conf)
      ackerman-uboot-entries status             what is ours on the ESP, and the space
      ackerman-uboot-entries remove             delete what this tool put on the ESP

    boot.bin and boot.bin.prev are never touched. Only EFI/ackerman/, loader/entries/ackerman-uboot-*,
    a loader.conf this tool wrote, and (with a U-Boot image configured) m1n1/boot.bin.uboot.
    """
    import argparse, datetime, gzip, hashlib, os, pathlib, re, shutil, struct, subprocess, sys, tempfile, zlib

    ESP = pathlib.Path(os.environ.get("ACKERMAN_UBOOT_ESP", "/boot"))
    PROFILES = pathlib.Path(os.environ.get("ACKERMAN_UBOOT_PROFILES", "/nix/var/nix/profiles"))
    OURS = ESP / "EFI" / "ackerman"
    ENTRIES = ESP / "loader" / "entries"
    LOADER_CONF = ESP / "loader" / "loader.conf"
    M1N1_DIR = ESP / "m1n1"
    SDBOOT = pathlib.Path(${builtins.toJSON sdboot})
    SDBOOT_NAME = "systemd-boot${efiArch}.efi"
    XZ = ${builtins.toJSON "${pkgs.xz}/bin/xz"}
    GENERATIONS = ${toString cfg.generations}
    TIMEOUT = ${toString cfg.timeout}
    RESERVE = ${toString cfg.reserveMiB} << 20
    EXTRA = ${builtins.toJSON (lib.concatStringsSep " " cfg.extraKernelParams)}
    PAYLOAD_UBOOT = ${builtins.toJSON (if ubootFile == null then "" else "${ubootFile}")}
    PAYLOAD_M1N1 = ${builtins.toJSON (if m1n1File == null then "" else "${m1n1File}")}
    # As ackerman-payload.py's CHOSEN, plus the marker build-uboot.sh puts in boot.bin.uboot
    CHOSEN = b"chosen.asahi,show-notch=1\nchosen.m5pro,n1=4\nchosen.m5pro,gpu=1\nchosen.ackerman,payload=uboot\n"
    DTB_NAME = ${builtins.toJSON config.ackerman.payload.dtbName}
    MARK = "# ackerman-uboot"
    PREFIX = "ackerman-uboot-gen"
    MiB = 1 << 20


    def die(msg):
        sys.exit(f"ackerman-uboot: {msg}")


    def note(msg):
        print(f"ackerman-uboot: {msg}")


    def sha(b):
        return hashlib.sha256(b).hexdigest()


    def esp_ready():
        os.listdir(ESP)  # /boot is an automount: touching it mounts it
        if not M1N1_DIR.is_dir():
            die(f"{M1N1_DIR} missing: is the ESP mounted on {ESP}?")


    def gunzip_all(b, what):
        out = b""
        while b:
            d = zlib.decompressobj(31)
            try:
                out += d.decompress(b)
            except zlib.error as ex:
                die(f"{what}: not gzip ({ex})")
            if not d.eof:
                die(f"{what}: truncated gzip member")
            b = d.unused_data
        return out


    def store_hash(path):
        parts = pathlib.Path(os.path.realpath(path)).parts
        if len(parts) < 4 or parts[1:3] != ("nix", "store"):
            die(f"{path} is not in the Nix store")
        return parts[3].split("-", 1)[0][:16], parts[3].split("-", 1)[1]


    def generations():
        """[(number, profile link, toplevel)], newest first."""
        out = []
        for p in PROFILES.glob("system-*-link"):
            m = re.fullmatch(r"system-(\d+)-link", p.name)
            if m:
                out.append((int(m.group(1)), p, pathlib.Path(os.path.realpath(p))))
        return sorted(out, reverse=True)


    def secrets(top):
        app = top / "append-initrd-secrets"
        if not app.exists():
            return b""
        with tempfile.TemporaryDirectory() as t:
            s = pathlib.Path(t) / "secrets"
            s.write_bytes(b"")
            subprocess.run([str(app), str(s)], check=True)
            return s.read_bytes()


    class Gen:
        def __init__(self, num, link, top):
            self.num, self.top = num, top
            kh, kname = store_hash(top / "kernel")
            # The kernel package's own EFI zboot image, if it ships one (kernel.nix, CONFIG_EFI_ZBOOT)
            self.zboot = pathlib.Path(os.path.realpath(top / "kernel")).parent / "vmlinuz.efi"
            self.kernel = f"{kh}-vmlinuz.efi" if self.zboot.is_file() else f"{kh}-Image.efi"
            self.release = kname
            self._secrets = secrets(top)
            ih, _ = store_hash(top / "initrd")
            tag = sha(self._secrets)[:8] if self._secrets else "nosecret"
            self.initrd = f"{ih}-{tag}-initrd.xz"
            self.params = (top / "kernel-params").read_text().strip()
            self.date = datetime.date.fromtimestamp(os.lstat(link).st_mtime).isoformat()

        def kernel_bytes(self):
            if self.zboot.is_file():
                z = self.zboot.read_bytes()
                # EFI zboot: an MZ/PE header with "zimg" at offset 4
                if z[:2] != b"MZ" or z[4:8] != b"zimg":
                    die(f"{self.zboot} is not an EFI zboot image")
                return z
            raw = gunzip_all((self.top / "kernel").read_bytes(), "kernel")
            if raw[:2] != b"MZ" or raw[56:60] != b"ARM\x64":
                die(f"{self.top}/kernel is not an arm64 EFI-stub Image")
            return raw

        def initrd_bytes(self):
            raw = gunzip_all((self.top / "initrd").read_bytes(), "initrd")
            if raw[:5] != b"07070":
                die(f"{self.top}/initrd is not a newc cpio")
            if self._secrets:
                raw += b"\0" * (-len(raw) % 4) + gunzip_all(self._secrets, "initrd secrets")
            # The kernel's XZ decoder takes CRC32 or no check, LZMA2 only.
            r = subprocess.run([XZ, "--check=crc32", "--lzma2=preset=9e", "-c"], input=raw,
                               stdout=subprocess.PIPE, check=True)
            return r.stdout

        def entry_name(self):
            return f"{PREFIX}{self.num}.conf"

        def entry(self):
            opts = f"init={self.top}/init {self.params} ackerman.boot=uboot {EXTRA}".strip()
            return (f"{MARK}: generated, edits are overwritten\n"
                    f"title NixOS on ackerman, generation {self.num}\n"
                    f"version {self.num} ({self.date}, {self.release})\n"
                    f"sort-key ackerman\n"
                    f"linux /EFI/ackerman/{self.kernel}\n"
                    f"initrd /EFI/ackerman/{self.initrd}\n"
                    f"options {opts}\n")


    def ours():
        return {f.name: f.stat().st_size for f in OURS.iterdir() if f.is_file()} if OURS.is_dir() else {}


    def write_verified(path, blob):
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".new")
        with open(tmp, "wb") as f:
            f.write(blob)
            f.flush()
            os.fsync(f.fileno())
        if sha(tmp.read_bytes()) != sha(blob):
            tmp.unlink()
            die(f"{tmp} read back wrong: nothing replaced")
        os.replace(tmp, path)
        fd = os.open(path.parent, os.O_RDONLY)
        os.fsync(fd)
        os.close(fd)


    def reserve():
        bb = M1N1_DIR / "boot.bin"
        size = bb.stat().st_size if bb.exists() else 80 * MiB
        return copies() * size + 20 * MiB + RESERVE


    def copies():
        """Payload copies the next install writes (ackerman-payload's rule): boot.bin, plus
        boot.bin.prev unless it is pinned."""
        return 1 if (M1N1_DIR / "prev.pinned").exists() else 2


    def loader_conf_ours():
        return not LOADER_CONF.exists() or LOADER_CONF.read_text().startswith(MARK)


    def write_loader_conf(default):
        if not loader_conf_ours():
            note(f"{LOADER_CONF} was not written by this tool: left alone (default not set)")
            return
        write_verified(LOADER_CONF, (
            f"{MARK}: generated by ackerman-uboot-entries (uboot.nix), edits are overwritten\n"
            f"timeout {TIMEOUT}\n"
            f"default {default}\n"
            "editor no\n"
            "auto-entries no\n"
            "auto-firmware no\n"
            "console-mode keep\n").encode())


    def payload_blob(top):
        if not (PAYLOAD_UBOOT and PAYLOAD_M1N1):
            return None
        dtb = (top / "dtbs" / DTB_NAME).read_bytes()
        if dtb[:4] != b"\xd0\x0d\xfe\xed" or struct.unpack(">I", dtb[4:8])[0] != len(dtb) or b"apple,j716c" not in dtb:
            die(f"{top}/dtbs/{DTB_NAME}: not a J716C devicetree")
        ub = pathlib.Path(PAYLOAD_UBOOT).read_bytes()
        if gzip.decompress(ub)[56:60] != b"ARM\x64":
            die(f"{PAYLOAD_UBOOT}: not a gzipped arm64 image")
        return pathlib.Path(PAYLOAD_M1N1).read_bytes() + CHOSEN + dtb + ub


    def install(toplevel):
        esp_ready()
        top = pathlib.Path(os.path.realpath(toplevel))
        gens = generations()
        first = next((g for g in gens if g[2] == top), None)
        if first is None:
            die(f"{top} is not a generation of {PROFILES}/system")
        order = [first] + [g for g in gens if g[2] != top][:GENERATIONS - 1]
        have = ours()
        blob = payload_blob(top)
        pay = M1N1_DIR / "boot.bin.uboot"
        pay_now = pay.stat().st_size if (blob is not None and pay.exists()) else 0
        budget = shutil.disk_usage(ESP).free + sum(have.values()) + pay_now - reserve()
        need = {SDBOOT_NAME: SDBOOT.read_bytes()}
        used = len(need[SDBOOT_NAME]) + (len(blob) if blob is not None else 0)
        keep = []
        with tempfile.TemporaryDirectory(prefix="ackerman-uboot-") as t:
            staged = {}
            for g in (Gen(*o) for o in order):
                add = 0
                for name, make in ((g.kernel, g.kernel_bytes), (g.initrd, g.initrd_bytes)):
                    if name in staged or name in need:
                        continue
                    if name in have:
                        staged[name] = None
                        add += have[name]
                    else:
                        p = pathlib.Path(t) / name
                        p.write_bytes(make())
                        staged[name] = p
                        add += p.stat().st_size
                if used + add > budget:
                    note(f"generation {g.num} left out: {(used + add) >> 20} MiB would leave less than "
                         f"{reserve() >> 20} MiB free ({copies()} x boot.bin + 20 + {RESERVE >> 20})")
                    for name in (g.kernel, g.initrd):
                        if name not in [x for k in keep for x in (k.kernel, k.initrd)]:
                            staged.pop(name, None)
                    break
                used += add
                keep.append(g)
            if not keep:
                note("no generation fits on the ESP: entries left as they were")
                return
            final = set(need) | {n for g in keep for n in (g.kernel, g.initrd)}
            # Free first, then write: the peak is the larger set, not both.
            for name in have:
                if name not in final:
                    (OURS / name).unlink()
            for f in ENTRIES.glob(f"{PREFIX}*.conf") if ENTRIES.is_dir() else []:
                if f.name not in {g.entry_name() for g in keep}:
                    f.unlink()
            if have.get(SDBOOT_NAME) != len(need[SDBOOT_NAME]) or sha((OURS / SDBOOT_NAME).read_bytes()) != sha(need[SDBOOT_NAME]):
                write_verified(OURS / SDBOOT_NAME, need[SDBOOT_NAME])
            for name, p in staged.items():
                if p is not None:
                    write_verified(OURS / name, p.read_bytes())
        for g in keep:
            write_verified(ENTRIES / g.entry_name(), g.entry().encode())
        write_loader_conf(keep[0].entry_name())
        if blob is not None and (not pay.exists() or sha(pay.read_bytes()) != sha(blob)):
            write_verified(pay, blob)
            note(f"m1n1/boot.bin.uboot = {sha(blob)[:16]} (staged only: boot.bin is untouched)")
        free = shutil.disk_usage(ESP).free
        note(f"entries for generation(s) {', '.join(str(g.num) for g in keep)}; default {keep[0].num}; "
             f"ours {sum(ours().values()) >> 20} MiB, ESP free {free >> 20} MiB (keeps {reserve() >> 20})")


    def set_default(n):
        esp_ready()
        e = ENTRIES / f"{PREFIX}{n}.conf"
        if not e.exists():
            die(f"no entry for generation {n} ({e})")
        write_loader_conf(e.name)
        note(f"default: generation {n}")


    def status():
        esp_ready()
        for name, size in sorted(ours().items()):
            print(f"{size:>10}  EFI/ackerman/{name}")
        for f in sorted(ENTRIES.glob(f"{PREFIX}*.conf")) if ENTRIES.is_dir() else []:
            print(" " * 10 + f"  loader/entries/{f.name}")
        if LOADER_CONF.exists():
            print(f"loader.conf ({'ours' if loader_conf_ours() else 'NOT ours'}): "
                  + " | ".join(LOADER_CONF.read_text().splitlines()[1:3]))
        print(f"ours {sum(ours().values()) >> 20} MiB; ESP free {shutil.disk_usage(ESP).free >> 20} MiB; "
              f"keeps {reserve() >> 20} MiB free for the payload installs")


    def remove():
        esp_ready()
        for name in ours():
            (OURS / name).unlink()
        for f in ENTRIES.glob(f"{PREFIX}*.conf") if ENTRIES.is_dir() else []:
            f.unlink()
        if LOADER_CONF.exists() and loader_conf_ours():
            LOADER_CONF.unlink()
        note("removed (m1n1/boot.bin.uboot, if any, is left for the operator)")


    def main():
        ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
        sub = ap.add_subparsers(dest="cmd", required=True)
        sub.add_parser("install").add_argument("toplevel")
        sub.add_parser("default").add_argument("generation", type=int)
        sub.add_parser("status")
        sub.add_parser("remove")
        a = ap.parse_args()
        {"install": lambda: install(a.toplevel), "default": lambda: set_default(a.generation),
         "status": status, "remove": remove}[a.cmd]()


    if __name__ == "__main__":
        main()
  '';

in
{
  options.ackerman.uboot = {
    enable = lib.mkEnableOption ''
      systemd-boot entries on the ESP for boot.bin.uboot (m1n1 -> U-Boot -> systemd-boot). Off by
      default; boot.bin stays the m1n1 payload either way'';

    generations = lib.mkOption {
      type = lib.types.ints.between 1 10;
      default = 2;
      description = ''
        Generations to give entries, the installed one first, then the newest others. Fewer are
        written when the ESP must keep N x boot.bin + 20 MiB + reserveMiB free (N = 1 while
        m1n1/prev.pinned exists, else 2).
      '';
    };

    timeout = lib.mkOption {
      type = lib.types.ints.between 0 30;
      default = 3;
      description = ''
        systemd-boot's menu timeout, in seconds. U-Boot has no keyboard on ackerman, so the menu
        only shows the list and boots the default. Keep it short: the A/B stage-1's 150 s
        watchdog runs until Linux takes it over.
      '';
    };

    reserveMiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 16;
      description = "Free space kept on top of the next payload install's own need (r1-logs, slack).";
    };

    extraKernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "efi=noruntime" ];
      description = "Added to every entry's command line (not to the m1n1 payloads).";
    };

    payload = {
      uboot = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          u-boot-nodtb.bin.gz (m5max-linux builds/private/uboot/build-uboot.sh). With this and
          `m1n1` set, every install also writes m1n1/boot.bin.uboot with the installed generation's
          DTB, so the U-Boot payload's tree follows the kernels. It is never copied to boot.bin.
        '';
      };
      m1n1 = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "The m1n1 stage-2 for boot.bin.uboot (the n1warm-gpu one boot-m1n1.nix uses).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.loader.external.enable;
        message = "ackerman.uboot needs boot-m1n1.nix (boot.loader.external)";
      }
      {
        assertion = (cfg.payload.uboot == null) == (cfg.payload.m1n1 == null);
        message = "ackerman.uboot.payload: set both uboot and m1n1, or neither";
      }
    ];
    # After boot-m1n1.nix's payload install, in its hook; never fails the switch
    ackerman.payload.afterInstall = ''
      ${entries}/bin/ackerman-uboot-entries install "$1" \
        || echo "ackerman-uboot: systemd-boot entries not updated (boot.bin is installed; the switch goes on)" >&2
    '';
    environment.systemPackages = [ entries ];
  };
}
