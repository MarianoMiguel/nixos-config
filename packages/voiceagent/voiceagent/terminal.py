"""The visible half of the voice agent: a real Claude Code terminal.

Driving the CLI headlessly meant every long turn looked like a hang -- nothing
to read, nothing to watch, no way to tell "thinking" from "broken". So the
agent no longer owns the conversation. It opens an ordinary Ghostty window
running `claude` and types into it, which makes the terminal the UI: progress,
tool output, permission prompts and history are all just there, and the
keyboard still works for anything voice cannot express.

The window is tracked by id, never re-found by app id. Matching on app id would
happily pick some other window and type a prompt into it, which is exactly the
failure where dictation lands in whatever box happened to have focus.
"""

from __future__ import annotations

import asyncio
import logging
import shutil

from . import keys

log = logging.getLogger("voiceagent.terminal")

APP_ID = "mariano.voiceagent"


class Terminal:
    def __init__(self, cwd: str, command: list[str] | None = None):
        self.cwd = cwd
        self.command = command or ["claude"]
        # The one window this agent owns. None until we spawn one.
        self.window_id: int | None = None

    async def _still_open(self) -> bool:
        if self.window_id is None:
            return False
        return any(window.get("id") == self.window_id for window in await keys.windows())

    async def _spawn(self) -> int | None:
        for binary in ("ghostty", "niri", "ydotool"):
            if shutil.which(binary) is None:
                log.error("%s is not on PATH", binary)
                return None

        before = {window.get("id") for window in await keys.windows()}
        log.info("opening a Claude Code terminal in %s", self.cwd)
        await keys.run(
            [
                "niri",
                "msg",
                "action",
                "spawn",
                "--",
                "ghostty",
                f"--class={APP_ID}",
                f"--working-directory={self.cwd}",
                "--title=Voice Agent",
                "-e",
                *self.command,
            ]
        )

        # Identify the window by what is new rather than by app id, so a second
        # agent window never gets confused with the first.
        for _ in range(80):
            await asyncio.sleep(0.25)
            for window in await keys.windows():
                if window.get("id") not in before and window.get("app_id") == APP_ID:
                    # Ghostty plus a cold `claude` needs a moment before it
                    # accepts keystrokes; typing early loses the first
                    # characters or lands in the trust prompt.
                    await asyncio.sleep(2.5)
                    return window.get("id")

        log.error("the terminal never appeared")
        return None

    async def ensure(self) -> int | None:
        """The agent's window, opening one if it is gone.

        Reusing the same window is what continues the conversation: the same
        `claude` process keeps its context, so the next thing said is a
        follow-up rather than a fresh session.
        """
        if await self._still_open():
            return self.window_id
        self.window_id = await self._spawn()
        return self.window_id

    async def send(self, text: str) -> bool:
        """Type one prompt into the agent's window and submit it."""
        text = " ".join(text.split())
        if not text:
            return False

        window_id = await self.ensure()
        if window_id is None:
            return False
        if not await keys.focus(window_id):
            return False

        # Re-check after focusing: if focus silently landed elsewhere, typing
        # would put the prompt into someone else's window.
        focused = await keys.focused_window()
        if focused is None or focused.get("id") != window_id:
            log.error("the agent window did not take focus; refusing to type")
            return False

        if not await keys.type_text(text):
            return False

        # Enter as a separate call: ydotool types the literal text, and a
        # newline inside `type` is not reliably delivered as a submit.
        await asyncio.sleep(0.1)
        if not await keys.press(*keys.ENTER):
            return False

        log.info("sent to Claude Code: %s", text[:120])
        return True

    async def interrupt(self) -> None:
        """Escape, which is how Claude Code cancels the turn in progress."""
        if not await self._still_open() or self.window_id is None:
            return
        if await keys.focus(self.window_id):
            await keys.press(*keys.ESCAPE)
