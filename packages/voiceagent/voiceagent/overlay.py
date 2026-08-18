"""Runs and feeds the floating panel.

The panel is a separate quickshell process reading a JSON file. Writing the
file rather than piping to the process means the overlay can start late, crash,
or be restarted without the session having to care, and the state is always
whatever was written last.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

# Imported as a submodule rather than `from . import theme`: the package's
# __init__ is still initialising when session.py pulls this in, so the
# attribute does not exist on the package object yet.
from .theme import radius as theme_radius
from .theme import resolve as resolve_theme
from .theme import signature as theme_signature

log = logging.getLogger("voiceagent.overlay")


def state_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / "voiceagent" / "overlay.json"


class Overlay:
    def __init__(self, quickshell: str, qml: Path):
        self.quickshell = quickshell
        self.qml = qml
        self.path = state_path()
        self._process: asyncio.subprocess.Process | None = None
        self._theme_signature: tuple = ()
        self._state: dict[str, Any] = {
            "mode": "idle",
            "level": 0.0,
            "partial": "",
            "lastSent": "",
            "showing": False,
            "colors": resolve_theme(),
            "radius": theme_radius(),
        }

    def refresh_theme(self, force: bool = False) -> bool:
        """Re-read the desktop palette if it changed.

        Polled rather than watched: the panel should follow a theme switch, but
        not badly enough to justify an inotify watch on four files.
        """
        signature = theme_signature()
        if not force and signature == self._theme_signature:
            return False
        self._theme_signature = signature
        colors = resolve_theme()
        corner = theme_radius()
        if colors != self._state.get("colors") or corner != self._state.get("radius"):
            self.update(colors=colors, radius=corner)
            return True
        return False

    def update(self, **fields: Any) -> None:
        """Rewrite the state file.

        Atomic via rename: FileView watches this path, and a torn read would
        show the panel a half-written JSON document.
        """
        self._state.update(fields)
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            handle = tempfile.NamedTemporaryFile(
                "w", dir=self.path.parent, prefix=".overlay-", delete=False
            )
            with handle:
                json.dump(self._state, handle)
            os.replace(handle.name, self.path)
        except OSError as exc:
            log.debug("cannot write overlay state: %s", exc)

    async def start(self) -> None:
        if self._process is not None and self._process.returncode is None:
            return
        if shutil.which(self.quickshell) is None:
            log.warning("%s is not on PATH; running without the panel", self.quickshell)
            return
        if not self.qml.exists():
            log.warning("no overlay at %s; running without the panel", self.qml)
            return

        self._process = await asyncio.create_subprocess_exec(
            self.quickshell,
            "-p",
            str(self.qml),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        log.info("panel up")

    async def stop(self) -> None:
        process, self._process = self._process, None
        if process is None or process.returncode is not None:
            return
        process.terminate()
        try:
            await asyncio.wait_for(process.wait(), timeout=3)
        except TimeoutError:
            with contextlib.suppress(ProcessLookupError):
                process.kill()
