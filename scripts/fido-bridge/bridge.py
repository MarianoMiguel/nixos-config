#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""On-demand FIDO HID relay. SSH stdin/stdout is the only network transport.

The Mac owns the physical HID connection. Linux creates a fixed FIDO-only UHID
device, then relays 64-byte reports. No credentials or PINs are logged or stored.
"""

import argparse
import errno
import fcntl
import json
import logging
import os
import pwd
import selectors
import shlex
import signal
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

MAGIC = b"BONHART-FIDO-1\n"
MAX_MESSAGE = 7609  # CTAPHID: 57 bytes + 128 continuation reports of 59 bytes.
BROADCAST = 0xFFFFFFFF
INIT, CBOR, CANCEL, ERROR = 6, 16, 17, 63
REPORT_DESCRIPTOR = bytes.fromhex(
    "06d0f10901a1010920150026ff007508954081020921150026ff00750895409102c0"
)


def read_exact(stream, length):
    result = bytearray()
    while len(result) < length:
        part = stream.read(length - len(result))
        if not part:
            raise EOFError("SSH connection closed")
        result.extend(part)
    return bytes(result)


def packets(cid, command, body=b""):
    if len(body) > MAX_MESSAGE:
        raise ValueError("CTAP message too large")
    yield (struct.pack(">IBH", cid, command | 0x80, len(body)) + body[:57]).ljust(64, b"\0")
    for sequence, offset in enumerate(range(57, len(body), 59)):
        yield (struct.pack(">IB", cid, sequence) + body[offset:offset + 59]).ljust(64, b"\0")


def permitted(command, body):
    """Allow browser authentication, never resets or key administration."""
    if command == 1:  # PING
        return True
    if command in (8, CANCEL):  # WINK, CANCEL
        return not body
    if command == INIT:
        return len(body) == 8
    if command == 3:  # U2F extended APDU: register, authenticate, version.
        return len(body) >= 4 and body[0] == 0 and body[1] in (1, 2, 3)
    if command != CBOR or not body:
        return False
    if body[0] in (1, 2, 4, 8):  # makeCredential, getAssertion, getInfo, getNextAssertion.
        return True
    if body[0] != 6:  # clientPIN: permit PIN authentication, not PIN set/change.
        return False
    from fido2 import cbor
    try:
        request = cbor.decode(body[1:])
        return isinstance(request, dict) and request.get(2) in (1, 2, 5, 6, 7, 9)
    except (ValueError, TypeError, IndexError, KeyError, RecursionError):
        return False


class Guard:
    """Bounded message assembly and separation from other Mac HID clients."""

    def __init__(self, reply):
        self.reply = reply
        self.fragments = {}
        self.nonces = {}
        self.channels = set()
        self.lock = threading.RLock()

    def error(self, cid, code):
        self.reply(next(packets(cid, ERROR, bytes([code]))))

    def incoming(self, report):
        if len(report) != 64:
            raise ValueError("Invalid HID report length")
        cid, marker = struct.unpack_from(">IB", report)
        with self.lock:
            now = time.monotonic()
            self.nonces = {n: t for n, t in self.nonces.items() if now - t < 10}
            for expired in [c for c, s in self.fragments.items() if now - s[0] > 3]:
                del self.fragments[expired]
                self.error(expired, 5)  # MSG_TIMEOUT
            if cid == 0 or (cid not in self.channels and not (cid == BROADCAST and marker == 0x86)):
                self.error(cid, 11)  # INVALID_CHANNEL
                return []
            if marker & 0x80:
                command, length = marker & 0x7F, struct.unpack_from(">H", report, 5)[0]
                self.fragments.pop(cid, None)
                if length > MAX_MESSAGE:
                    self.error(cid, 3)
                    return []
                if len(self.fragments) >= 16:
                    self.error(cid, 6)
                    return []
                state = [now, command, length, bytearray(report[7:7 + length]), [report], 0]
            else:
                state = self.fragments.pop(cid, None)
                if state is None or marker != state[5]:
                    self.error(cid, 4)  # INVALID_SEQ
                    return []
                state[3].extend(report[5:5 + max(0, state[2] - len(state[3]))])
                state[4].append(report)
                state[5] += 1
            if len(state[3]) < state[2]:
                self.fragments[cid] = state
                return []
            _, command, _, body, original, _ = state
            body = bytes(body)
            if not permitted(command, body):
                if command == CBOR:
                    self.reply(next(packets(cid, CBOR, b"\x27")))  # OPERATION_DENIED
                else:
                    self.error(cid, 1)
                return []
            if command == INIT:
                if len(self.nonces) >= 16 or len(self.channels) >= 1024:
                    self.error(cid, 6)
                    return []
                self.nonces[body] = now
            return original

    def outgoing(self, report):
        if len(report) != 64:
            raise ValueError("Invalid physical HID report length")
        cid, marker = struct.unpack_from(">IB", report)
        with self.lock:
            if cid == BROADCAST and marker == 0x86:
                nonce = report[7:15]
                timestamp = self.nonces.pop(nonce, None)
                if timestamp is None or time.monotonic() - timestamp >= 10:
                    return False
                channel = struct.unpack_from(">I", report, 15)[0]
                if struct.unpack_from(">H", report, 5)[0] != 17 or channel in (0, BROADCAST):
                    raise ValueError("Invalid CTAPHID initialization response")
                self.channels.add(channel)
                return True
            return cid in self.channels


def descriptors():
    from fido2.hid import list_descriptors
    return [d for d in list_descriptors() if d.vid == 0x1050 and
            d.report_size_in == 64 and d.report_size_out == 64]


def serve(product):
    from fido2.hid import open_connection
    # The upstream Mac backend logs idle read timeouts. Do not enable its raw
    # CTAP debug/traffic logging, which can disclose authentication payloads.
    logging.getLogger("fido2").disabled = True
    logging.getLogger("fido2.hid.macos").disabled = True
    matches = [d for d in descriptors() if d.pid == product]
    if len(matches) != 1:
        raise RuntimeError("Connect exactly one YubiKey matching the selected product ID")
    descriptor = matches[0]
    lock_dir = Path.home() / "Library/Application Support/Bonhart/fido-bridge"
    lock_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_file = open(lock_dir / f"{product:04x}.lock", "a")
    fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    connection = open_connection(descriptor)
    output_lock = threading.Lock()
    write_lock = threading.Lock()
    stopped = threading.Event()

    def emit(report):
        with output_lock:
            sys.stdout.buffer.write(report)
            sys.stdout.buffer.flush()

    guard = Guard(emit)
    metadata = json.dumps({"vendor": descriptor.vid, "product": descriptor.pid}).encode()
    sys.stdout.buffer.write(MAGIC + struct.pack(">I", len(metadata)) + metadata)
    sys.stdout.buffer.flush()

    def receive():
        try:
            while not stopped.is_set():
                try:
                    report = connection.read_packet()
                except OSError as error:
                    if str(error) == "Failed reading a response" and any(d.path == descriptor.path for d in descriptors()):
                        continue  # Idle, not a disconnected key.
                    raise
                if guard.outgoing(report):
                    emit(report)
        except Exception:
            if not stopped.is_set():
                print("Physical key disconnected or HID transport failed", file=sys.stderr, flush=True)
                os._exit(1)  # Wake the peer even when stdin is idle.

    threading.Thread(target=receive, daemon=True).start()
    try:
        while True:
            report = read_exact(sys.stdin.buffer, 64)
            approved = guard.incoming(report)
            with write_lock:
                for packet in approved:
                    connection.write_packet(packet)
    finally:
        stopped.set()
        with write_lock:
            for channel in guard.channels:
                try:
                    connection.write_packet(next(packets(channel, CANCEL)))
                except OSError:
                    pass
        # Process exit releases the Mac HID handle, callbacks and lock.


def uhid_create(vendor, product):
    return struct.pack("=I128s64s64sHHIIII", 11, b"Bonhart Remote YubiKey",
                       b"bonhart-fido/ssh", b"bonhart-fido", len(REPORT_DESCRIPTOR),
                       3, vendor, product, 1, 0) + REPORT_DESCRIPTOR


def uhid_output(event):
    event = event.ljust(4380, b"\0")
    kind = struct.unpack_from("=I", event)[0]
    if kind == 6:
        size, report_type = struct.unpack_from("=HB", event, 4100)
        # hidraw write() may include the zero report-ID byte even for an
        # unnumbered descriptor; UHID preserves it on some kernel paths.
        if size == 65 and event[4] == 0 and report_type == 1:
            return event[5:69]
        if size != 64 or report_type != 1:
            raise ValueError("Unexpected UHID output report")
        return event[4:68]
    return None


def frontend(product, host, remote_command):
    if not sys.platform.startswith("linux") or os.geteuid() != 0:
        raise RuntimeError("Use remote-yubikey start (UHID initialization needs administrator authentication)")
    uid = int(os.environ.get("PKEXEC_UID", "-1"))
    if uid <= 0:
        raise RuntimeError("Start through pkexec as your normal user")
    account = pwd.getpwuid(uid)
    fd = os.open("/dev/uhid", os.O_RDWR | os.O_CLOEXEC | os.O_NONBLOCK)
    # Open only this fixed device while privileged. SSH, all network input and
    # descriptor processing run after permanently dropping root and groups.
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(uid)
    os.environ.clear()
    os.environ.update(HOME=account.pw_dir, USER=account.pw_name, LOGNAME=account.pw_name,
                      PATH="/run/current-system/sw/bin", LANG="C.UTF-8")
    os.chdir(account.pw_dir)
    ssh = subprocess.Popen([
        "/run/current-system/sw/bin/ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes",
        "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3",
        "--", host, remote_command + " serve --product " + shlex.quote(f"{product:04x}")],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
    try:
        # A failed remote command cannot leave a ghost virtual authenticator.
        signal.alarm(20)
        if read_exact(ssh.stdout, len(MAGIC)) != MAGIC:
            raise RuntimeError("Unexpected bridge protocol")
        size = struct.unpack(">I", read_exact(ssh.stdout, 4))[0]
        if size > 256:
            raise RuntimeError("Invalid bridge greeting")
        meta = json.loads(read_exact(ssh.stdout, size))
        if meta != {"vendor": 0x1050, "product": product}:
            raise RuntimeError("Remote key does not match selection")
        signal.alarm(0)
        os.write(fd, uhid_create(0x1050, product))
        print(f"Connected: Mac YubiKey 1050:{product:04x}. Touch the key on the Mac when prompted.", flush=True)
        selector = selectors.DefaultSelector()
        selector.register(fd, selectors.EVENT_READ, "hid")
        selector.register(ssh.stdout, selectors.EVENT_READ, "ssh")
        buffered = bytearray()
        os.set_blocking(ssh.stdout.fileno(), False)
        while True:
            for key, _ in selector.select():
                if key.data == "ssh":
                    chunk = os.read(ssh.stdout.fileno(), 4096)
                    if not chunk:
                        raise EOFError("Mac connection closed; virtual key removed")
                    buffered.extend(chunk)
                    while len(buffered) >= 64:
                        report = bytes(buffered[:64])
                        del buffered[:64]
                        os.write(fd, struct.pack("=IH", 12, 64) + report)
                else:
                    event = os.read(fd, 4380)
                    report = uhid_output(event)
                    if report is not None:
                        ssh.stdin.write(report)
                    kind = struct.unpack_from("=I", event)[0]
                    if kind in (9, 13):  # FIDO uses interrupt reports, not feature reports.
                        request_id = struct.unpack_from("=I", event, 4)[0]
                        os.write(fd, struct.pack("=IIH", 10 if kind == 9 else 14, request_id, errno.EIO))
    finally:
        signal.alarm(0)
        os.close(fd)  # Kernel destroys the virtual HID device on close.
        ssh.stdin.close()
        try:
            ssh.wait(timeout=5)
        except subprocess.TimeoutExpired:
            ssh.terminate()
            try:
                ssh.wait(timeout=2)
            except subprocess.TimeoutExpired:
                ssh.kill()
                ssh.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("serve", "list", "frontend"))
    parser.add_argument("--product", type=lambda value: int(value, 16), default=0x0407)
    parser.add_argument("--host", default="mariano@100.115.44.59")
    parser.add_argument("--remote-command", default="'/Users/mariano/Library/Application Support/Bonhart/fido-bridge/.venv/bin/python' '/Users/mariano/Library/Application Support/Bonhart/fido-bridge/bridge.py'")
    args = parser.parse_args()
    if args.product not in (0x0407, 0x0402):
        parser.error("Only the two reviewed YubiKey product IDs are supported")
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Bridge greeting timed out")))
    if args.mode == "list":
        for descriptor in descriptors():
            print(f"1050:{descriptor.pid:04x} {descriptor.product_name or 'YubiKey'}")
    elif args.mode == "serve":
        serve(args.product)
    else:
        frontend(args.product, args.host, args.remote_command)


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        print("FIDO bridge disconnected", file=sys.stderr)
    except Exception as error:
        # Exception strings from HID or CBOR libraries can contain request data.
        print(f"FIDO bridge failed ({type(error).__name__}); check SSH access and the selected key", file=sys.stderr)
        sys.exit(1)
