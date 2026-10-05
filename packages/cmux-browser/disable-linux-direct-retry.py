"""Guard the pinned Linux binary against a macOS-only renderer retry loop.

151.0.7922.64 calls EnsureDirectAttached on Linux even though that frontend
rejects BeginCmuxTerminalHostInputCutover. Cancellation destroys/re-attaches the
working mirror every 200 ms, clearing its frame. Equivalent source fix is in
linux-direct-renderer.patch. This one-byte early return leaves Linux's existing
Ghostty renderer, input, PTYs, resize handling and Chromium sandbox intact.

The upstream Debian release is a stripped Chromium binary. Verify the complete
instruction span and the source-location reference before applying the fix;
a changed upstream build MUST fail, never silently patch a different function.
Remove this workaround once upstream gates direct rendering by platform.
"""
import hashlib
import struct
import sys
from pathlib import Path

binary = Path(sys.argv[1])
entry = 0xE6D6010  # file offset; virtual address 0xE6D7010
with binary.open('r+b') as stream:
    stream.seek(entry)
    code = stream.read(0x340)
    expected = '3651ade567bbacded44992df0c3b2e3ab09cb1e0166f12e0f346d597650fde39'
    if hashlib.sha256(code).hexdigest() != expected:
        raise SystemExit('cmux Linux workaround: unrecognized renderer code; review upstream')
    stream.seek(0xE6D6145)
    lea = stream.read(7)
    if lea[:3] != bytes.fromhex('48 8d 35'):
        raise SystemExit('cmux Linux workaround: missing source-location reference')
    target = 0xE6D7145 + 7 + struct.unpack('<i', lea[3:])[0]
    stream.seek(target)
    if stream.read(21) != b'EnsureDirectAttached\0':
        raise SystemExit('cmux Linux workaround: unexpected function identity')
    stream.seek(entry)
    stream.write(b'\xc3')  # ret, before the original function prologue
print('cmux: disabled the unsupported macOS direct-renderer retry on Linux')
