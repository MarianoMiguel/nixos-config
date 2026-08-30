"""The two things speech can do here.

`agent` sends one prompt to a real Claude Code terminal you can watch, then
closes the microphone. One utterance per press is deliberate: a session left
listening picks up the room, the terminal, and your own thinking-out-loud, and
posts all of it to the agent as follow-up prompts.

`dictate` types what you say into whatever window has focus, and keeps
listening until you press the key again, because dictating a paragraph is
several utterances with pauses in it.

Both show the same panel, so "is it hearing me" has one answer in both modes.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import time
from typing import Any

from . import keys
from .audio import Recorder
from .cleanup import Cleaner
from .config import Config
from .overlay import Overlay
from .stt import Transcriber
from .terminal import Terminal

log = logging.getLogger("voiceagent.session")

STOP_PHRASES = frozenset(
    {
        "stop listening", "goodbye", "good bye", "end session", "exit voice",
        "close voice", "stop voice", "that's all", "thats all",
    }
)
CANCEL_PHRASES = frozenset({"cancel that", "never mind", "nevermind", "stop that", "scratch that"})


def _normalise(text: str) -> str:
    return "".join(c for c in text.lower() if c.isalnum() or c.isspace()).strip()


class Session:
    def __init__(self, config: Config, broadcast):
        self.config = config
        self.broadcast = broadcast

        self.mode: str | None = None
        self.state = "idle"
        self.transcript: list[dict[str, str]] = []

        self.loop = asyncio.get_running_loop()
        self.recorder = Recorder(
            self.loop,
            device=config.input_device,
            aggressiveness=config.vad_aggressiveness,
            end_ms=config.utterance_end_ms,
        )
        self.transcriber = Transcriber(config.whisper_endpoint, config.whisper_timeout)
        self.cleaner = Cleaner(config)
        self.terminal = Terminal(cwd=str(config.cwd), command=config.terminal_command)
        self.overlay = Overlay(config.quickshell, config.overlay_qml_path())

        self._task: asyncio.Task[None] | None = None
        self._level_task: asyncio.Task[None] | None = None
        self._running = False

    # -- state -------------------------------------------------------------

    @property
    def running(self) -> bool:
        return self._running

    def publish(self, **extra: Any) -> None:
        self.broadcast(
            {
                "type": "state",
                "state": self.state,
                "mode": self.mode,
                "running": self._running,
                "transcript": self.transcript[-20:],
                "pending": None,
                **extra,
            }
        )

    def set_state(self, state: str) -> None:
        if state != self.state:
            log.info("state: %s -> %s", self.state, state)
        self.state = state
        self.overlay.update(mode=state)
        self.publish()

    def add_line(self, role: str, text: str) -> None:
        self.transcript.append({"role": role, "text": text, "at": time.strftime("%H:%M:%S")})
        self.publish()

    # -- lifecycle ---------------------------------------------------------

    async def start(self, mode: str = "agent") -> str:
        if self._running:
            # Pressing the other key while one mode is live should switch, not
            # silently do nothing.
            if mode != self.mode:
                await self.stop()
            else:
                return "already running"

        self._running = True
        self.mode = mode
        # Belt and braces: a crash between muting and stopping must not leave
        # the next session unable to hear.
        self.recorder.muted = False
        self.overlay.refresh_theme(force=True)
        self.overlay.update(showing=True, partial="", lastSent="", target=mode)
        await self.overlay.start()
        self.set_state("starting")

        if mode == "agent":
            # Open the terminal before listening, so the first thing said has
            # somewhere to land and you can see where it is going.
            if await self.terminal.ensure() is None:
                self.overlay.update(mode="error", partial="Could not open the Claude Code terminal")
                self._running = False
                self.mode = None
                await asyncio.sleep(3)
                self.overlay.update(showing=False)
                self.set_state("idle")
                return "could not open the terminal"

        self.recorder.start()
        self._task = asyncio.create_task(self._listen_loop())
        self._level_task = asyncio.create_task(self._level_loop())
        self.set_state("listening")
        return f"started ({mode})"

    async def stop(self) -> str:
        if not self._running:
            return "not running"
        self._running = False
        self.mode = None
        # The agent path mutes before typing and then stops, so without this
        # the mute survives into the next session and the microphone is deaf
        # with no indication why: no waveform, no utterances, nothing typed.
        self.recorder.muted = False

        for task in (self._task, self._level_task):
            if task is not None:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        self._task = self._level_task = None

        self.recorder.stop()
        self.set_state("idle")
        self.overlay.update(showing=False, partial="", level=0)
        await self.overlay.stop()
        return "stopped"

    async def toggle(self, mode: str = "agent") -> str:
        if self._running and self.mode == mode:
            return await self.stop()
        return await self.start(mode)

    # -- loops -------------------------------------------------------------

    async def _level_loop(self) -> None:
        """Feed the panel's blurb, and close dictation once you stop talking."""
        ticks = 0
        while self._running:
            await asyncio.sleep(0.06)
            if self.state == "listening":
                self.overlay.update(level=round(self.recorder.level, 3))

            if self.mode == "dictate" and self._idle_for() > self.config.dictation_idle_secs:
                log.info(
                    "no speech for %.1fs, closing dictation",
                    self.config.dictation_idle_secs,
                )
                asyncio.create_task(self.stop())
                return

            ticks += 1
            if ticks % 50 == 0:
                self.overlay.refresh_theme()

    def _idle_for(self) -> float:
        """Seconds since speech was last heard.

        Only counts while actually listening: transcribing, cleaning up and
        typing all take time during which the microphone is deliberately not
        being listened to, and counting those would close the session in the
        middle of handling what was just said.
        """
        if self.state != "listening":
            self.recorder.last_voice_at = time.monotonic()
            return 0.0
        return time.monotonic() - self.recorder.last_voice_at

    async def _listen_loop(self) -> None:
        while self._running:
            utterance = await self.recorder.utterances.get()

            self.set_state("transcribing")
            raw = await self.transcriber.transcribe(utterance.pcm)
            if not raw:
                self.set_state("listening")
                continue

            spoken = _normalise(raw)

            if spoken in STOP_PHRASES:
                self.add_line("user", raw)
                asyncio.create_task(self.stop())
                return

            if spoken in CANCEL_PHRASES:
                self.add_line("user", raw)
                self.overlay.update(partial="", lastSent="cancelled")
                if self.mode == "agent":
                    await self.terminal.interrupt()
                self.set_state("listening")
                continue

            # Show the raw transcript straight away, then replace it with the
            # tidied one: waiting for the cleanup pass would leave the panel
            # blank for the second it takes.
            self.overlay.update(partial=raw)
            text = await self.cleaner.clean(raw)
            if text != raw:
                self.overlay.update(partial=text)
            self.add_line("user", text)

            if self.mode == "agent":
                await self._send_to_agent(text)
                return

            await self._type_here(text)

    async def _send_to_agent(self, text: str) -> None:
        self.set_state("sending")
        # Stop hearing before typing: ydotool's keystrokes are silent, but the
        # terminal's output and the room are not, and anything picked up now
        # would be posted to the agent as a second prompt.
        self.recorder.muted = True
        sent = await self.terminal.send(text)

        if sent:
            self.overlay.update(partial="", lastSent=text)
            self.set_state("sent")
            await asyncio.sleep(1.6)
        else:
            self.overlay.update(mode="error", partial="Could not reach the agent window")
            self.add_line("system", "could not type into the Claude Code window")
            await asyncio.sleep(2.5)

        # One prompt per press. Alt+S again for the next turn, into the same
        # terminal, so the conversation continues where it left off.
        await self.stop()

    async def _type_here(self, text: str) -> None:
        self.set_state("typing")
        target = await keys.focused_window()
        if target is not None and target.get("app_id") == "mariano.voiceagent":
            # Dictation is for your own windows. Typing into the agent's
            # terminal here would submit a prompt nobody asked for.
            self.overlay.update(mode="error", partial="Focus a window to dictate into")
            await asyncio.sleep(2)
            self.set_state("listening")
            return

        self.recorder.muted = True
        try:
            ok = await keys.type_text(text)
        finally:
            self.recorder.muted = False

        if ok:
            self.overlay.update(partial="", lastSent=text)
        else:
            self.overlay.update(mode="error", partial="Could not type")
            await asyncio.sleep(1.5)

        if self._running:
            self.set_state("listening")

    # -- kept for the control socket ---------------------------------------

    def interrupt_speech(self) -> None:
        asyncio.create_task(self.terminal.interrupt())

    def resolve_approval(self, approved: bool) -> bool:
        """Approvals live in the terminal now, where Claude Code draws them."""
        return False
