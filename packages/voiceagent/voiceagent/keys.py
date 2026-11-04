"""Synthetic keystrokes, and asking GNOME Shell about windows.

ydotool types through uinput, so it reaches whatever window has focus without
a compositor protocol of its own.

Windows come from the Vicinae GNOME Shell extension (`gnomeExtensions.vicinae`,
installed by modules/nixos/vicinae.nix), which exports
org.gnome.Shell.Extensions.Windows on the session bus: List, Activate and
GetFocusedWindowSync, each window as JSON with its id, title and wm_class (the
Wayland app id). GNOME has no other way to ask for one window by id: Shell's
own Eval is closed to callers since GNOME 41.
"""

from __future__ import annotations

import asyncio
import json
import logging
import shutil

log = logging.getLogger("voiceagent.keys")

ENTER = ("28:1", "28:0")
ESCAPE = ("1:1", "1:0")

SHELL = "org.gnome.Shell"
WINDOWS_PATH = "/org/gnome/Shell/Extensions/Windows"
WINDOWS_IFACE = "org.gnome.Shell.Extensions.Windows"


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


async def _call(method: str, *args: str) -> object | None:
    """One call on the extension's window service; its JSON reply, decoded."""
    code, out = await run(
        ["busctl", "--user", "--json=short", "call", SHELL, WINDOWS_PATH, WINDOWS_IFACE, method, *args]
    )
    if code:
        log.error("GNOME Shell window service: %s failed: %s", method, out.strip())
        return None
    return parse_reply(out)


def parse_reply(out: str) -> object | None:
    """busctl's {"type": "s", "data": ["<json>"]} to the JSON inside, if any."""
    try:
        data = json.loads(out).get("data") or []
        return json.loads(data[0]) if data and isinstance(data[0], str) else None
    except (ValueError, AttributeError, IndexError):
        return None


def as_window(raw: object) -> dict | None:
    """One window in the shape the rest of the agent uses (id, app_id, title)."""
    if not isinstance(raw, dict) or not isinstance(raw.get("id"), int):
        return None
    return {"id": raw["id"], "app_id": raw.get("wm_class") or "", "title": raw.get("title") or ""}


async def windows() -> list[dict]:
    listed = await _call("List")
    if not isinstance(listed, list):
        return []
    return [window for window in map(as_window, listed) if window is not None]


async def focused_window() -> dict | None:
    return as_window(await _call("GetFocusedWindowSync"))


async def focus(window_id: int) -> bool:
    code, out = await run(
        ["busctl", "--user", "call", SHELL, WINDOWS_PATH, WINDOWS_IFACE, "Activate", "u", str(window_id)]
    )
    if code:
        log.error("cannot focus window %s: %s", window_id, out.strip())
        return False
    # Focus is asynchronous; typing immediately can land in the previous window.
    await asyncio.sleep(0.15)
    return True
