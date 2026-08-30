"""Synthetic keystrokes, and asking niri about windows.

ydotool rather than wtype throughout: niri 26.04 still carries
niri-wm/niri#2314, where the focused window stops receiving physical
keystrokes once a wtype process exits.
"""

from __future__ import annotations

import asyncio
import json
import logging
import shutil

log = logging.getLogger("voiceagent.keys")

ENTER = ("28:1", "28:0")
ESCAPE = ("1:1", "1:0")


async def run(argv: list[str], timeout: float = 20.0) -> tuple[int, str]:
    if shutil.which(argv[0]) is None:
        return 127, f"{argv[0]} is not on PATH"
    try:
        process = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        out, _ = await asyncio.wait_for(process.communicate(), timeout=timeout)
    except TimeoutError:
        return 124, f"{argv[0]} timed out"
    except OSError as exc:
        return 1, str(exc)
    return process.returncode or 0, out.decode("utf-8", "replace")


async def type_text(text: str) -> bool:
    """Type into whatever currently has focus."""
    if not text:
        return False
    code, out = await run(["ydotool", "type", "--key-delay", "2", "--", text], timeout=120.0)
    if code:
        log.error("typing failed: %s", out.strip())
        return False
    return True


async def press(*codes: str) -> bool:
    code, out = await run(["ydotool", "key", *codes])
    if code:
        log.error("key press failed: %s", out.strip())
        return False
    return True


async def windows() -> list[dict]:
    code, out = await run(["niri", "msg", "--json", "windows"])
    if code:
        log.error("cannot list windows: %s", out.strip())
        return []
    try:
        return json.loads(out)
    except ValueError:
        return []


async def focused_window() -> dict | None:
    for window in await windows():
        if window.get("is_focused"):
            return window
    return None


async def focus(window_id: int) -> bool:
    code, out = await run(["niri", "msg", "action", "focus-window", "--id", str(window_id)])
    if code:
        log.error("cannot focus window %s: %s", window_id, out.strip())
        return False
    # Focus is asynchronous; typing immediately can land in the previous window.
    await asyncio.sleep(0.15)
    return True
