#!/usr/bin/env python3
"""ackerman-payload - build and install ackerman's m1n1 payloads from NixOS generations.

ackerman boots with no UEFI and no boot menu: the A/B m1n1 stage-1 (macOS's boot object) loads
/boot/m1n1/boot.bin from the ESP, and after an unclean boot (a hang, a watchdog reset, a power-button
hold) it tries /boot/m1n1/boot.bin.prev first. A payload is one file (m5max-linux tools/mk-payload.py):

    m1n1 stage-2 | chosen.bootargs=...\\n | chosen.* lines | Image.gz | DTB | initrd (one gzip member)

  ackerman-payload install TOPLEVEL [--daily]   build TOPLEVEL's payload and make it boot.bin
                                                (a self-test payload unless --daily; NixOS's
                                                boot-loader hook runs this for every switch/boot)
  ackerman-payload promote                      the booted generation passed its self-test: its
                                                payload, without the self-test, becomes boot.bin
  ackerman-payload build TOPLEVEL OUT [--daily] only write the payload to OUT
  ackerman-payload build TOPLEVEL OUT --rescue  the rescue: TOPLEVEL's initrd stops at
                                                ackerman-rescue.target (tether, SSH on 2222, a
                                                console shell, disk tools; nothing is opened)
  ackerman-payload status                       what is on the ESP

boot.bin.prev is the fallback, the last payload known to come up. It is never a payload that hasn't
proven itself: install moves the running boot.bin there only when this boot came from boot.bin
(not the fallback slot) and is not itself a self-test, as m5max-linux's deploy plan does. While
/boot/m1n1/prev.pinned exists, boot.bin.prev is not touched at all (the Arch daily stays the
fallback until NixOS has proven itself; delete the file to let generations rotate).

A self-test payload carries m5.selftest=1: ackerman-selftest.service gives it 90 s after
network-online to reach 1.1.1.1, then promotes it, or puts boot.bin.prev back and reboots. The
initrd waits for the LUKS passphrase before any of that, so the timer starts only after the unlock.
"""
import argparse, datetime, gzip, hashlib, os, pathlib, re, shutil, struct, subprocess, sys, tempfile, zlib

M1N1 = pathlib.Path("@m1n1@")            # the stage-2, from the private input
M1N1_SIZE = 0x420000                      # n1warm-gpu, exactly
DTB_NAME = "apple/t6050-j716c.dtb"
CHOSEN = b"chosen.asahi,show-notch=1\nchosen.m5pro,n1=4\nchosen.m5pro,gpu=1\n"
ESP = pathlib.Path("/boot")
DIR = ESP / "m1n1"
LOG = DIR / "ackerman-payloads.log"
MAX_ARGS = 1024                           # m1n1's MAX_VAR_SIZE
# The system's own m1n1 variables on top of CHOSEN (boot-m1n1.nix, ackerman.payload.chosen), as
# "key=value key=value": the DCP hand-off, chosen.m5,t6050-display=1, is one
CHOSEN_EXTRA = "@chosen@"
VAR = re.compile(r"[A-Za-z0-9,._-]+")


def die(msg):
    sys.exit(f"ackerman-payload: {msg}")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def gz_members(b, what):
    n, out = 0, b""
    while b:
        d = zlib.decompressobj(31)
        try:
            out += d.decompress(b)
        except zlib.error as ex:
            die(f"{what}: not gzip ({ex})")
        if not d.eof:
            die(f"{what}: truncated gzip member")
        n += 1
        b = d.unused_data
    return n, out


def initrd_with_secrets(top):
    """The generation's initrd plus its secrets (the initrd SSH host key), as ONE gzip member:
    m1n1 keeps only the last gzip member of a payload, and NixOS's secret appender adds its own."""
    _, raw = gz_members((top / "initrd").read_bytes(), "initrd")
    if raw[:5] != b"07070":
        die("initrd is not a newc cpio")
    app = top / "append-initrd-secrets"
    if app.exists():
        with tempfile.TemporaryDirectory() as t:
            s = pathlib.Path(t) / "secrets"
            s.write_bytes(b"")
            subprocess.run([str(app), str(s)], check=True)
            b = s.read_bytes()
            if b:
                _, sraw = gz_members(b, "initrd secrets")
                raw += b"\0" * (-len(raw) % 4) + sraw
    return gzip.compress(raw, compresslevel=9, mtime=0)


RESCUE = "rd.systemd.unit=ackerman-rescue.target rd.luks=0"


def chosen_vars(add="", drop="", base=None):
    """A payload's m1n1 variables, in order: CHOSEN, then the system's (CHOSEN_EXTRA), or `base`
    (a payload's own, for promote); then --chosen KEY=VALUE adds or changes, --no-chosen KEY removes."""
    v = {}
    tokens = list(add.split())
    if base is None:
        for line in CHOSEN.decode().splitlines():
            k, _, val = line[len("chosen."):].partition("=")
            v[k] = val
        tokens = CHOSEN_EXTRA.split() + tokens
    else:
        v = dict(base)
    for t in tokens:
        k, eq, val = t.partition("=")
        if not eq or not VAR.fullmatch(k) or not (val == "" or VAR.fullmatch(val)) or k == "bootargs":
            die(f"chosen variable {t!r}: not KEY=VALUE (letters, digits and ,._-; not bootargs)")
        v[k] = val
    for k in drop.split():
        v.pop(k, None)
    return v


def payload_parts(blob):
    """What a payload was built with: its chosen.* variables (bootargs apart) and its DTB."""
    v, pos = {}, M1N1_SIZE
    while blob[pos:pos + 7] == b"chosen.":
        end = blob.index(b"\n", pos)
        k, _, val = blob[pos + 7:end].decode().partition("=")
        if k != "bootargs":
            v[k] = val
        pos = end + 1
    d = zlib.decompressobj(31)
    d.decompress(blob[pos:])
    rest = d.unused_data
    if not d.eof or rest[:4] != b"\xd0\x0d\xfe\xed":
        die("boot.bin: no kernel and DTB where a payload has them")
    return v, rest[:struct.unpack(">I", rest[4:8])[0]]


def build(top, daily, rescue=False, extra="", hold=False, dtb_file=None, chosen=None, dtb_bytes=None):
    top = pathlib.Path(os.path.realpath(top))
    m1n1 = M1N1.read_bytes()
    if len(m1n1) != M1N1_SIZE:
        die(f"{M1N1} is {len(m1n1):#x} bytes, expected {M1N1_SIZE:#x}")
    kernel = (top / "kernel").read_bytes()
    n, raw = gz_members(kernel, "kernel")
    if n != 1 or raw[56:60] != b"ARM\x64":
        die("kernel is not one gzip member of an arm64 Image")
    # --dtb: another device tree for this payload (the PMP-off variant, ...); a promote passes the
    # booted payload's own
    if dtb_bytes is not None:
        dtb = dtb_bytes
    else:
        dtb = pathlib.Path(dtb_file).read_bytes() if dtb_file else (top / "dtbs" / DTB_NAME).read_bytes()
    if dtb[:4] != b"\xd0\x0d\xfe\xed" or struct.unpack(">I", dtb[4:8])[0] != len(dtb) or b"apple,j716c" not in dtb:
        die(f"{DTB_NAME}: not a J716C device tree")
    initrd = initrd_with_secrets(top)
    params = (top / "kernel-params").read_text().strip()
    args = f"init={top}/init {params}" + ("" if daily or rescue else " m5.selftest=1")
    # --hold: the self-test reverts a boot without network but doesn't promote it; promote by hand
    # once the desktop is checked (a boot can pass the network test with a black screen)
    if hold and not daily and not rescue:
        args += " m5.hold=1"
    # --extra: switches for this payload only (of_disable=..., pmc.agents=0, ...); a hand promote
    # keeps them
    if extra.strip():
        args += " " + " ".join(extra.split())
    if rescue:
        args += " " + RESCUE
    if "\n" in args or not args.isascii() or len(args) >= MAX_ARGS:
        die(f"bootargs must be one ASCII line under {MAX_ARGS} bytes ({len(args)})")
    if chosen is None:
        chosen = chosen_vars()
    lines = "".join(f"chosen.{k}={v}\n" for k, v in chosen.items()).encode()
    blob = m1n1 + f"chosen.bootargs={args}\n".encode() + lines + kernel + dtb + initrd
    return blob, args


def esp_ready():
    if not (DIR / "boot.bin").exists():
        # /boot is an automount: touching it mounts it
        os.listdir(ESP)
    if not DIR.is_dir():
        die(f"{DIR} missing: is the ESP mounted on /boot?")


def cmdline():
    return pathlib.Path("/proc/cmdline").read_text()


def booted_from_primary():
    try:
        slot = pathlib.Path("/proc/device-tree/chosen/m5pro,boot-slot").read_bytes().rstrip(b"\0")
    except OSError:
        return True   # a stage-1 without the A/B variable: there is only one slot
    return slot.startswith(b"primary")


def write_verified(path, blob):
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


def log(line):
    with open(LOG, "a") as f:
        f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} {line}\n")


def install(top, daily, reason="install", extra="", hold=False, chosen=None, dtb_bytes=None):
    esp_ready()
    blob, args = build(top, daily, extra=extra, hold=hold, chosen=chosen, dtb_bytes=dtb_bytes)
    # write_verified puts the new file beside the old one, then renames it over: boot.bin needs one
    # payload's room, and boot.bin.prev another unless it is pinned (then it isn't written)
    copies = 1 if (DIR / "prev.pinned").exists() else 2
    need = copies * len(blob) + 20 * 2**20
    free = shutil.disk_usage(ESP).free
    if free < need:
        die(f"ESP has {free >> 20} MB free, needs {need >> 20}: prune /boot/r1-logs, or the boot "
            f"menu's entries (ackerman-uboot-entries remove), first")
    cur = DIR / "boot.bin"
    digest = sha(blob)
    if cur.exists() and sha(cur.read_bytes()) == digest:
        print(f"boot.bin already is this payload ({digest[:16]})")
        return
    prev = DIR / "boot.bin.prev"
    if (DIR / "prev.pinned").exists():
        note = "boot.bin.prev pinned (prev.pinned): untouched"
    elif "m5.selftest=1" in cmdline():
        note = "the running payload is a self-test: boot.bin.prev untouched"
    elif not booted_from_primary():
        note = "this boot came from the fallback slot: boot.bin.prev untouched"
    elif not cur.exists():
        note = "no boot.bin yet: boot.bin.prev untouched"
    else:
        write_verified(prev, cur.read_bytes())
        note = f"boot.bin.prev = the payload running now ({sha(prev.read_bytes())[:16]})"
    write_verified(cur, blob)
    mode = "daily" if daily else ("self-test, held" if hold else "self-test")
    log(f"{reason}: boot.bin = {digest[:16]} ({mode}, {len(blob)} bytes) {os.path.realpath(top)}; {note}")
    print(f"boot.bin = {digest[:16]}, {mode}, {len(blob) >> 20} MB, for {os.path.realpath(top)}")
    print(note)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("install"); p.add_argument("toplevel"); p.add_argument("--daily", action="store_true")
    p.add_argument("--hold", action="store_true"); p.add_argument("--extra", default="")
    p = sub.add_parser("build"); p.add_argument("toplevel"); p.add_argument("out"); p.add_argument("--daily", action="store_true")
    p.add_argument("--rescue", action="store_true")
    p.add_argument("--hold", action="store_true"); p.add_argument("--extra", default="")
    p.add_argument("--dtb", default=None)
    # m1n1 variables for this payload only: --chosen "m5,t6050-isp=aura", --no-chosen "m5,t6050-display"
    p.add_argument("--chosen", default=""); p.add_argument("--no-chosen", default="")
    sub.add_parser("promote")
    sub.add_parser("status")
    a = ap.parse_args()
    if a.cmd == "build":
        chosen = chosen_vars(a.chosen, a.no_chosen)
        blob, args = build(a.toplevel, a.daily, a.rescue, a.extra, a.hold, a.dtb, chosen=chosen)
        pathlib.Path(a.out).write_bytes(blob)
        print(f"{a.out}: {len(blob)} bytes, sha256 {sha(blob)}\nbootargs {args}")
        print("chosen   " + " ".join(f"{k}={v}" for k, v in chosen.items()))
    elif a.cmd == "install":
        install(a.toplevel, a.daily, extra=a.extra, hold=a.hold)
    elif a.cmd == "promote":
        if "m5.selftest=1" not in cmdline():
            die("this boot is not a self-test: nothing to promote")
        # A generation installed since this boot (a switch) owns boot.bin now: promoting the booted
        # one would put the older generation back over it (2026-11-08 22:08, when a switch re-ran
        # the self-test). boot.bin's own init= names the generation it boots.
        esp_ready()
        cur = DIR / "boot.bin"
        booted = os.path.realpath("/run/booted-system")
        m = re.search(rb"chosen\.bootargs=init=(/nix/store/[^/\s]+)/init", cur.read_bytes()) if cur.exists() else None
        if m and os.path.realpath(m.group(1).decode()) != booted:
            print(f"boot.bin is {m.group(1).decode()}, installed since this boot ({booted}): not promoting over it")
            log(f"promote skipped: boot.bin is {m.group(1).decode()}, not the booted {booted}")
            return
        # The switches this payload was built with stay in the daily: --extra (from the command
        # line), and its m1n1 variables and DTB (--chosen/--no-chosen, --dtb: from boot.bin, which
        # is the booted payload once its init= matches)
        params = (pathlib.Path(booted) / "kernel-params").read_text().split()
        skip = set(params) | {"m5.selftest=1", "m5.hold=1"}
        extra = " ".join(t for t in cmdline().split() if t not in skip and not t.startswith("init="))
        chosen = dtb = None
        if m:
            base, dtb = payload_parts(cur.read_bytes())
            chosen = chosen_vars(base=base)
        install("/run/booted-system", daily=True, reason="promote (self-test passed)", extra=extra,
                chosen=chosen, dtb_bytes=dtb)
    elif a.cmd == "status":
        esp_ready()
        for f in sorted(DIR.glob("boot.bin*")):
            print(f"{sha(f.read_bytes())[:16]}  {f.stat().st_size:>10}  {f.name}")
        print(f"prev.pinned: {'yes' if (DIR / 'prev.pinned').exists() else 'no'}")
        if LOG.exists():
            print(LOG.read_text().splitlines()[-5:])


if __name__ == "__main__":
    main()
