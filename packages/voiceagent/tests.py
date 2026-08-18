"""Tests for the parts that decide things.

The audio device, the compositor and Claude Code are all out of reach here.
What is covered is the logic that can silently do the wrong thing: recognising
the spoken control phrases, endpointing an utterance, and the level meter that
tells the user whether the microphone is hearing them at all.
"""

import json
import unittest

from voiceagent.session import CANCEL_PHRASES, STOP_PHRASES, _normalise


class SpokenCommands(unittest.TestCase):
    def test_stop_phrases_are_recognised(self):
        for phrase in ["Stop listening.", "GOODBYE", "that's all", "End session!"]:
            self.assertIn(_normalise(phrase), STOP_PHRASES, phrase)

    def test_cancel_phrases_are_recognised(self):
        for phrase in ["Never mind.", "cancel that", "Scratch that!"]:
            self.assertIn(_normalise(phrase), CANCEL_PHRASES, phrase)

    def test_ordinary_speech_is_not_a_command(self):
        # These must reach Claude Code, not be swallowed as control phrases.
        for phrase in [
            "stop the dev server",
            "cancel the deployment",
            "say goodbye to the old parser",
            "open dolphin",
        ]:
            words = _normalise(phrase)
            self.assertNotIn(words, STOP_PHRASES, phrase)
            self.assertNotIn(words, CANCEL_PHRASES, phrase)

    def test_normalise_strips_punctuation_and_case(self):
        self.assertEqual(_normalise("  Open Dolphin, please!  "), "open dolphin please")


class LevelMeter(unittest.TestCase):
    def setUp(self):
        import asyncio

        from voiceagent.audio import Recorder

        self.loop = asyncio.new_event_loop()
        self.recorder = Recorder(self.loop)

    def tearDown(self):
        self.loop.close()

    @staticmethod
    def _frame(amplitude):
        import struct

        from voiceagent.audio import FRAME_MS, RATE

        n = RATE * FRAME_MS // 1000
        return struct.pack(f"<{n}h", *([amplitude] * n))

    def test_silence_reads_zero(self):
        self.recorder._track_level(self._frame(0))
        self.assertEqual(self.recorder.level, 0.0)

    def test_loud_audio_reads_high(self):
        self.recorder._track_level(self._frame(30000))
        self.assertGreater(self.recorder.level, 0.8)

    def test_attack_is_immediate_and_release_is_gradual(self):
        # A meter that fell as fast as it rose would flicker and read as
        # broken; one that never fell would look stuck at full.
        self.recorder._track_level(self._frame(30000))
        peak = self.recorder.level
        self.recorder._track_level(self._frame(0))
        after = self.recorder.level
        self.assertLess(after, peak)
        self.assertGreater(after, 0.0)


class OverlayState(unittest.TestCase):
    def test_state_file_is_valid_json_after_each_update(self):
        import os
        import tempfile
        from pathlib import Path

        from voiceagent.overlay import Overlay

        with tempfile.TemporaryDirectory() as tmp:
            os.environ["XDG_RUNTIME_DIR"] = tmp
            overlay = Overlay("quickshell", Path(tmp) / "missing.qml")
            overlay.update(showing=True, mode="listening", level=0.4)
            overlay.update(partial="open dolphin")
            payload = json.loads(overlay.path.read_text())

        self.assertEqual(payload["mode"], "listening")
        self.assertEqual(payload["partial"], "open dolphin")
        # Earlier fields must survive a partial update, or the panel blanks
        # every time one value changes.
        self.assertTrue(payload["showing"])
        self.assertEqual(payload["level"], 0.4)


class Theming(unittest.TestCase):
    """The panel has to match the desktop, including a custom theme file."""

    def setUp(self):
        import os
        import tempfile

        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        os.environ["XDG_CONFIG_HOME"] = root + "/config"
        os.environ["XDG_STATE_HOME"] = root + "/state"
        self.config = __import__("pathlib").Path(root) / "config" / "DankMaterialShell"
        self.state = __import__("pathlib").Path(root) / "state" / "DankMaterialShell"
        self.config.mkdir(parents=True)
        self.state.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def _write(self, path, payload):
        path.write_text(json.dumps(payload))

    def test_falls_back_when_nothing_is_readable(self):
        from voiceagent import theme

        colors = theme.resolve()
        self.assertEqual(colors, theme.FALLBACK)

    def test_reads_the_builtin_theme(self):
        from voiceagent import theme

        self._write(self.config / "settings.json", {})
        self._write(self.config / "theme.json", {"dark": {"primary": "#112233"}})
        self.assertEqual(theme.resolve()["primary"], "#112233")

    def test_custom_theme_file_wins(self):
        # This is how the themeport palette reaches the shell; reading
        # theme.json instead would leave the panel a different colour from
        # every other surface on the desktop.
        from voiceagent import theme

        custom = self.config / "themes" / "themeport" / "theme.json"
        custom.parent.mkdir(parents=True)
        self._write(custom, {"dark": {"primary": "#d4bd99"}})
        self._write(self.config / "theme.json", {"dark": {"primary": "#6fb8e3"}})
        self._write(self.config / "settings.json", {"customThemeFile": str(custom)})
        self.assertEqual(theme.resolve()["primary"], "#d4bd99")

    def test_light_mode_uses_the_light_variant(self):
        from voiceagent import theme

        self._write(self.config / "settings.json", {})
        self._write(
            self.config / "theme.json",
            {"dark": {"primary": "#000000"}, "light": {"primary": "#ffffff"}},
        )
        self._write(self.state / "session.json", {"isLightMode": True})
        self.assertEqual(theme.resolve()["primary"], "#ffffff")

    def test_missing_roles_fall_back_individually(self):
        from voiceagent import theme

        self._write(self.config / "settings.json", {})
        self._write(self.config / "theme.json", {"dark": {"primary": "#112233"}})
        colors = theme.resolve()
        self.assertEqual(colors["primary"], "#112233")
        self.assertEqual(colors["error"], theme.FALLBACK["error"])

    def test_garbage_values_are_ignored(self):
        from voiceagent import theme

        self._write(self.config / "settings.json", {})
        self._write(self.config / "theme.json", {"dark": {"primary": "not-a-colour"}})
        self.assertEqual(theme.resolve()["primary"], theme.FALLBACK["primary"])


class CornerRadius(unittest.TestCase):
    """The panel must square off with the rest of the desktop."""

    def setUp(self):
        import os
        import pathlib
        import tempfile

        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        os.environ["XDG_CONFIG_HOME"] = root + "/config"
        os.environ["XDG_STATE_HOME"] = root + "/state"
        self.config = pathlib.Path(root) / "config" / "DankMaterialShell"
        self.toggle = (
            pathlib.Path(root) / "state" / "nixos-config" / "dotfiles" / "niri" / "toggles" / "radius.kdl"
        )
        self.config.mkdir(parents=True)
        self.toggle.parent.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_uses_the_dms_setting(self):
        from voiceagent import theme

        self.config.joinpath("settings.json").write_text(json.dumps({"cornerRadius": 18}))
        self.assertEqual(theme.radius(), 18)

    def test_the_squared_off_toggle_wins(self):
        # Mod+Ctrl+B writes this rule. It only reaches niri windows, and the
        # panel is a layer-shell surface, so without this it would stay the one
        # rounded thing on a squared-off desktop.
        from voiceagent import theme

        self.config.joinpath("settings.json").write_text(json.dumps({"cornerRadius": 18}))
        self.toggle.write_text("window-rule {\n    geometry-corner-radius 0\n}\n")
        self.assertEqual(theme.radius(), 0)

    def test_toggle_off_restores_the_dms_setting(self):
        from voiceagent import theme

        self.config.joinpath("settings.json").write_text(json.dumps({"cornerRadius": 18}))
        self.toggle.write_text("// Window corners use the current DMS radius.\n")
        self.assertEqual(theme.radius(), 18)

    def test_falls_back_without_config(self):
        from voiceagent import theme

        self.assertEqual(theme.radius(), theme.FALLBACK_RADIUS)

    def test_the_toggle_is_part_of_the_change_signature(self):
        # Otherwise toggling rounding mid-session would not restyle the panel.
        from voiceagent import theme

        self.assertIn(str(self.toggle), theme.watched_paths())


class CleanupGuard(unittest.IsolatedAsyncioTestCase):
    """The cleanup pass must never make dictation worse."""

    def _cleaner(self, **overrides):
        from voiceagent.cleanup import Cleaner
        from voiceagent.config import Config

        config = Config(**overrides)
        return Cleaner(config)

    async def test_disabled_returns_the_original(self):
        cleaner = self._cleaner(cleanup=False)
        self.assertEqual(await cleaner.clean("hello there"), "hello there")

    async def test_empty_input_is_left_alone(self):
        cleaner = self._cleaner(cleanup=True)
        self.assertEqual(await cleaner.clean("   "), "   ")

    async def test_a_missing_claude_falls_back_to_the_raw_transcript(self):
        # A dictation that types nothing is worse than one that types an
        # untidied sentence, so every failure path returns the input.
        cleaner = self._cleaner(cleanup=True)
        cleaner.model = "nonexistent"
        import unittest.mock

        with unittest.mock.patch(
            "asyncio.create_subprocess_exec", side_effect=FileNotFoundError("no claude")
        ):
            self.assertEqual(await cleaner.clean("open dolphin"), "open dolphin")


class MuteLeak(unittest.IsolatedAsyncioTestCase):
    """The agent path mutes before typing; that must not outlive the session."""

    async def _session(self):
        from voiceagent.config import Config
        from voiceagent.session import Session

        return Session(Config(cleanup=False), broadcast=lambda payload: None)

    async def test_stop_clears_a_leftover_mute(self):
        # Without this, one Alt+S leaves every later dictation deaf: no
        # waveform, no utterances, nothing typed, and no error to explain it.
        session = await self._session()
        session._running = True
        session.recorder.muted = True
        await session.stop()
        self.assertFalse(session.recorder.muted)

    async def test_idle_timer_only_runs_while_listening(self):
        # Transcribing and typing are not silence; counting them would close
        # the session while it is still handling what was just said.
        session = await self._session()
        session.recorder.last_voice_at = 0.0
        session.state = "transcribing"
        self.assertEqual(session._idle_for(), 0.0)
        session.state = "listening"
        self.assertGreater(session._idle_for(), 0.0)


class Endpointing(unittest.IsolatedAsyncioTestCase):
    """Feeds synthetic audio through the VAD loop, with no sound device."""

    @staticmethod
    def _frames(kind, count):
        import math
        import struct

        from voiceagent.audio import FRAME_MS, RATE

        samples_per_frame = RATE * FRAME_MS // 1000
        out = []
        for index in range(count):
            block = []
            for offset in range(samples_per_frame):
                if kind == "silence":
                    block.append(0)
                    continue
                t = (index * samples_per_frame + offset) / RATE
                value = sum(
                    amp * math.sin(2 * math.pi * 130 * harmonic * t)
                    for harmonic, amp in enumerate([1.0, 0.6, 0.4, 0.25, 0.15], start=1)
                )
                value *= 0.6 + 0.4 * math.sin(2 * math.pi * 4 * t)
                block.append(max(-32768, min(32767, int(value * 6000))))
            out.append(struct.pack(f"<{samples_per_frame}h", *block))
        return out

    async def _run(self, script, **kwargs):
        import asyncio

        from voiceagent.audio import Recorder

        recorder = Recorder(asyncio.get_running_loop(), **kwargs)
        for kind, count in script:
            for frame in self._frames(kind, count):
                recorder._frames.put(frame)
        recorder._frames.put(None)
        await asyncio.to_thread(recorder._consume)
        # _consume hands utterances over with call_soon_threadsafe, so the loop
        # needs a turn before they land on the queue.
        await asyncio.sleep(0.05)

        collected = []
        while not recorder.utterances.empty():
            collected.append(recorder.utterances.get_nowait())
        return collected

    async def test_two_utterances_between_silences(self):
        utterances = await self._run(
            [("silence", 15), ("voiced", 50), ("silence", 40), ("voiced", 50), ("silence", 40)]
        )
        self.assertEqual(len(utterances), 2)
        for utterance in utterances:
            self.assertGreater(utterance.seconds, 0.5)

    async def test_silence_alone_emits_nothing(self):
        self.assertEqual(await self._run([("silence", 200)]), [])

    async def test_a_short_blip_is_not_an_utterance(self):
        # A cough or a door is not a prompt. Emitting one would type noise into
        # the Claude Code terminal and submit it.
        self.assertEqual(
            await self._run([("silence", 10), ("voiced", 6), ("silence", 40)], min_ms=400), []
        )

    async def test_trailing_silence_is_trimmed(self):
        [utterance] = await self._run([("silence", 10), ("voiced", 50), ("silence", 60)])
        self.assertLess(utterance.seconds, 1.5)

    async def test_muting_drops_everything(self):
        import asyncio

        from voiceagent.audio import Recorder

        recorder = Recorder(asyncio.get_running_loop())
        recorder.muted = True
        for frame in self._frames("voiced", 100):
            recorder._frames.put(frame)
        recorder._frames.put(None)
        await asyncio.to_thread(recorder._consume)
        await asyncio.sleep(0.05)
        self.assertTrue(recorder.utterances.empty())
        # Muted must also park the meter, or the panel shows bars bouncing
        # while nothing is being heard.
        self.assertEqual(recorder.level, 0.0)


if __name__ == "__main__":
    unittest.main()
