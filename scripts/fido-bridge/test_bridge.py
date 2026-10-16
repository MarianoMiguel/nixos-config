# SPDX-License-Identifier: MIT
import io
import struct
import unittest
from fido2 import cbor
from bridge import Guard, packets, permitted, read_exact, uhid_create, uhid_output, BROADCAST


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.replies = []
        self.guard = Guard(self.replies.append)
        self.guard.channels.add(42)

    def test_only_our_init_response_is_forwarded(self):
        request = next(packets(BROADCAST, 6, b"12345678"))
        self.assertEqual(self.guard.incoming(request), [request])
        response = b"abcdefgh" + struct.pack(">IBBBBB", 99, 2, 1, 0, 0, 5)
        self.assertFalse(self.guard.outgoing(next(packets(BROADCAST, 6, response))))
        response = b"12345678" + response[8:]
        self.assertTrue(self.guard.outgoing(next(packets(BROADCAST, 6, response))))
        self.assertIn(99, self.guard.channels)
        self.assertFalse(self.guard.outgoing(next(packets(77, 16, b"local Mac response"))))

    def test_fragmented_request_is_validated_before_forwarding(self):
        frames = list(packets(42, 16, b"\x01" + b"x" * 300))
        for report in frames[:-1]:
            self.assertEqual(self.guard.incoming(report), [])
        self.assertEqual(self.guard.incoming(frames[-1]), frames)

    def test_reset_and_management_never_reach_key(self):
        for command in (7, 10, 11, 12, 13, 0x40, 0x41):
            self.assertFalse(permitted(16, bytes([command])))
            self.assertEqual(self.guard.incoming(next(packets(42, 16, bytes([command])))), [])
            self.assertEqual(self.replies[-1][7], 0x27)
        self.assertFalse(permitted(0x40, b""))

    def test_pin_auth_allowed_but_pin_changes_denied(self):
        for subcommand in (1, 2, 5, 6, 7, 9):
            self.assertTrue(permitted(16, b"\x06" + cbor.encode({1: 1, 2: subcommand})))
        for subcommand in (3, 4, 0, 255):
            self.assertFalse(permitted(16, b"\x06" + cbor.encode({1: 1, 2: subcommand})))
        self.assertFalse(permitted(16, b"\x06\xff"))

    def test_u2f_and_basic_commands(self):
        for command in (1, 2, 3):
            self.assertTrue(permitted(3, bytes([0, command, 0, 0])))
        self.assertFalse(permitted(3, b"\x00\xff\x00\x00"))
        self.assertTrue(permitted(17, b""))
        self.assertFalse(permitted(17, b"x"))
        self.assertFalse(permitted(4, b"\xff"))

    def test_rejects_invalid_channel_and_sequence(self):
        self.assertEqual(self.guard.incoming(next(packets(77, 1, b"hi"))), [])
        frames = list(packets(42, 16, b"\x01" * 200))
        self.guard.incoming(frames[0])
        self.assertEqual(self.guard.incoming(frames[2]), [])
        self.assertEqual(self.replies[-1][7], 4)

    def test_rejects_oversize_and_short_reports(self):
        with self.assertRaises(ValueError):
            self.guard.incoming(b"short")
        report = struct.pack(">IBH", 42, 0x90, 65535).ljust(64, b"\0")
        self.assertEqual(self.guard.incoming(report), [])
        self.assertEqual(self.replies[-1][7], 3)

    def test_cancel_discards_partial_request(self):
        self.guard.incoming(next(packets(42, 16, b"\x01" * 200)))
        report = next(packets(42, 17))
        self.assertEqual(self.guard.incoming(report), [report])
        self.assertNotIn(42, self.guard.fragments)

    def test_maximum_size_and_packet_sequence(self):
        frames = list(packets(42, 1, b"x" * 7609))
        self.assertEqual(len(frames), 129)
        self.assertEqual(frames[-1][4], 127)
        for report in frames[:-1]:
            self.assertEqual(self.guard.incoming(report), [])
        self.assertEqual(self.guard.incoming(frames[-1]), frames)
        with self.assertRaises(ValueError):
            list(packets(42, 1, b"x" * 7610))

    def test_partial_or_closed_transport(self):
        self.assertEqual(read_exact(io.BytesIO(b"abc"), 3), b"abc")
        with self.assertRaises(EOFError):
            read_exact(io.BytesIO(b"abc"), 4)

    def test_uhid_descriptor_is_fido_only(self):
        event = uhid_create(0x1050, 0x0407)
        self.assertEqual(struct.unpack_from("=I", event)[0], 11)
        self.assertEqual(struct.unpack_from("=HHII", event, 260), (34, 3, 0x1050, 0x0407))
        self.assertTrue(event.endswith(bytes.fromhex("06d0f10901a1010920150026ff007508954081020921150026ff00750895409102c0")))

    def test_uhid_output_abi(self):
        report = next(packets(42, 1, b"hi"))
        event = struct.pack("=I", 6) + report.ljust(4096, b"\0") + struct.pack("=HB", 64, 1)
        self.assertEqual(uhid_output(event), report)
        with self.assertRaises(ValueError):
            uhid_output(event[:-3] + struct.pack("=HB", 66, 1))

    def test_hidraw_zero_report_id_prefix(self):
        report = next(packets(BROADCAST, 6, b"12345678"))
        event = struct.pack("=I", 6) + (b"\x00" + report).ljust(4096, b"\0") + struct.pack("=HB", 65, 1)
        self.assertEqual(uhid_output(event), report)
        with self.assertRaises(ValueError):
            uhid_output(event[:4] + b"\x01" + event[5:])


if __name__ == "__main__":
    unittest.main()
