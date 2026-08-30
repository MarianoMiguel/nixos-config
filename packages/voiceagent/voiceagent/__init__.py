"""Speak to a real Claude Code terminal.

Bound to Alt+S in niri. A floating panel shows the input level and what was
heard; the words themselves are typed into an ordinary Ghostty window running
`claude`, so the work is visible and a follow-up is just more speech into the
same session. Speech recognition runs on this machine.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import logging
import signal
import sys
from pathlib import Path
from typing import Any

from . import config as config_module
from .control import ControlServer, send_command

log = logging.getLogger("voiceagent")


async def run_daemon(config: config_module.Config) -> int:
    from .session import Session

    stop = asyncio.get_running_loop().create_future()
    server: ControlServer | None = None
    session: Session | None = None

    async def handle(command: str, message: dict[str, Any]) -> dict[str, Any]:
        assert session is not None
        if command == "start":
            return {"type": "ack", "result": await session.start("agent")}
        if command == "stop":
            return {"type": "ack", "result": await session.stop()}
        if command == "toggle":
            return {"type": "ack", "result": await session.toggle("agent")}
        if command == "dictate":
            return {"type": "ack", "result": await session.toggle("dictate")}
        if command == "status":
            return {
                "type": "state",
                "state": session.state,
                "mode": session.mode,
                "running": session.running,
                "transcript": session.transcript[-20:],
                "pending": None,
            }
        if command in ("approve", "deny"):
            resolved = session.resolve_approval(command == "approve")
            return {"type": "ack", "result": "resolved" if resolved else "nothing pending"}
        if command == "interrupt":
            session.interrupt_speech()
            return {"type": "ack", "result": "interrupted"}
        if command == "quit":
            if not stop.done():
                stop.set_result(None)
            return {"type": "ack", "result": "stopping"}
        return {"type": "error", "error": f"unknown command {command!r}"}

    server = ControlServer(handle)
    from .session import Session as _Session

    session = _Session(config, broadcast=lambda payload: server.broadcast(payload))

    try:
        await server.start()
    except (RuntimeError, OSError) as exc:
        log.error("%s", exc)
        return 1

    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        with contextlib.suppress(NotImplementedError, ValueError):
            loop.add_signal_handler(signum, lambda: stop.done() or stop.set_result(None))

    log.info("ready: Alt+A dictates into the focused window, Alt+S prompts an agent")
    log.info("agent terminals open in %s", config.cwd)
    session.publish()

    try:
        await stop
    finally:
        await session.stop()
        await server.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="voiceagent",
        description="Local spoken agent for Claude Code, Codex, and the desktop.",
    )
    parser.add_argument("-c", "--config", type=Path, help="config file")
    parser.add_argument("-v", "--debug", action="store_true")
    parser.add_argument(
        "command",
        nargs="?",
        default="daemon",
        choices=[
            "daemon", "start", "stop", "toggle", "dictate", "status",
            "approve", "deny", "interrupt", "quit",
        ],
        help=(
            "daemon runs the service; `toggle` sends one spoken prompt to a "
            "Claude Code terminal; `dictate` types what you say into the "
            "focused window; the rest talk to a running daemon"
        ),
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )

    if args.command == "daemon":
        config = config_module.load(args.config)
        try:
            return asyncio.run(run_daemon(config))
        except KeyboardInterrupt:
            return 0

    try:
        reply = asyncio.run(send_command(args.command))
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        return 1
    print(json.dumps(reply))
    return 0 if reply.get("type") != "error" else 1
