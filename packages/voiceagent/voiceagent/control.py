"""The unix socket that the tap daemon and the DMS widget both talk to.

Commands go in, state broadcasts come out, newline-delimited JSON both ways.
Keeping this a plain socket rather than routing through DMS means the agent
still works with the shell's plugin disabled -- the widget is a view, not the
control path.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from pathlib import Path
from typing import Any, Awaitable, Callable

log = logging.getLogger("voiceagent.control")


def socket_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / "voiceagent.sock"


class ControlServer:
    def __init__(self, handler: Callable[[str, dict[str, Any]], Awaitable[dict[str, Any]]]):
        self.handler = handler
        self.path = socket_path()
        self._server: asyncio.AbstractServer | None = None
        self._subscribers: set[asyncio.StreamWriter] = set()
        self._last_state: dict[str, Any] = {}

    async def start(self) -> None:
        # A socket left behind by a killed daemon would make bind fail. Only
        # remove it once nothing is listening.
        if self.path.exists():
            try:
                _, writer = await asyncio.open_unix_connection(str(self.path))
                writer.close()
                raise RuntimeError(f"another voiceagent is already listening on {self.path}")
            except (ConnectionRefusedError, FileNotFoundError, OSError):
                self.path.unlink(missing_ok=True)

        self._server = await asyncio.start_unix_server(self._serve, path=str(self.path))
        self.path.chmod(0o600)
        log.info("listening on %s", self.path)

    async def _serve(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self._subscribers.add(writer)
        try:
            if self._last_state:
                await self._send(writer, self._last_state)
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    message = json.loads(line)
                except ValueError:
                    await self._send(writer, {"type": "error", "error": "malformed json"})
                    continue
                command = str(message.get("cmd") or "")
                try:
                    reply = await self.handler(command, message)
                except Exception as exc:  # a bad command must not drop the session
                    log.exception("command %r failed", command)
                    reply = {"type": "error", "error": str(exc)}
                await self._send(writer, reply)
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            self._subscribers.discard(writer)
            writer.close()

    async def _send(self, writer: asyncio.StreamWriter, payload: dict[str, Any]) -> None:
        try:
            writer.write(json.dumps(payload).encode("utf-8") + b"\n")
            await writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            self._subscribers.discard(writer)

    def broadcast(self, state: dict[str, Any]) -> None:
        """Push state to every connected viewer.

        Cached so a widget that connects mid-session sees the current state
        immediately instead of an empty pill until the next change.
        """
        self._last_state = state
        for writer in list(self._subscribers):
            asyncio.create_task(self._send(writer, state))

    async def close(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
        for writer in list(self._subscribers):
            writer.close()
        self.path.unlink(missing_ok=True)


async def send_command(command: str, **extra: Any) -> dict[str, Any]:
    """One-shot client used by the `voiceagent <command>` subcommands."""
    path = socket_path()
    try:
        reader, writer = await asyncio.open_unix_connection(str(path))
    except (ConnectionRefusedError, FileNotFoundError):
        raise RuntimeError(f"voiceagent daemon is not running (no {path})") from None

    try:
        # The server greets a new connection with the current state; skip it so
        # the reply we return is the answer to this command.
        greeting = asyncio.create_task(reader.readline())
        writer.write(json.dumps({"cmd": command, **extra}).encode("utf-8") + b"\n")
        await writer.drain()
        try:
            first = await asyncio.wait_for(greeting, timeout=0.5)
        except TimeoutError:
            first = b""
        line = await asyncio.wait_for(reader.readline(), timeout=10)
        if not line:
            line = first
        return json.loads(line) if line else {}
    finally:
        writer.close()
