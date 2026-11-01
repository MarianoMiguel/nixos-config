"""Follow the desktop's current colours.

The panel is a standalone quickshell surface, so it cannot read a theme
itself. It gets its colours from here: themeport's rendered palette
(`meta.json`: the mode, the accent and the background), with neutral roles
for everything the palette does not say.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

log = logging.getLogger("voiceagent.theme")

# Used until themeport has rendered a palette, and for any role it leaves
# out. Deliberately neutral rather than pretty: if these show up, the lookup
# failed.
FALLBACK: dict[str, str] = {
    "primary": "#7dd3fc",
    "secondary": "#b4e4f6",
    "tertiary": "#c084fc",
    "error": "#f87171",
    "warning": "#fbbf24",
    "surface": "#11151c",
    "surfaceContainer": "#11151c",
    "surfaceText": "#e2e8f0",
    "surfaceVariantText": "#94a3b8",
    "outline": "#4a6b80",
}

# Text that reads on a light background, for a light palette.
LIGHT_TEXT: dict[str, str] = {
    "surfaceText": "#1a2740",
    "surfaceVariantText": "#536177",
}

ROLES = tuple(FALLBACK)


def meta_path() -> Path:
    """Where themeport writes the palette it applied (themeport.state_root)."""
    if env := os.environ.get("THEMEPORT_STATE"):
        return Path(env) / "meta.json"
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "nixos-config" / "dotfiles" / "themeport" / "meta.json"


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def _hex(value: object) -> str | None:
    if isinstance(value, str) and len(value) == 7 and value.startswith("#"):
        try:
            int(value[1:], 16)
        except ValueError:
            return None
        return value
    return None


def resolve() -> dict[str, str]:
    """The colours of the palette themeport last applied."""
    meta = _read_json(meta_path())
    colors = dict(FALLBACK)
    if meta.get("mode") == "light":
        colors.update(LIGHT_TEXT)
    if accent := _hex(meta.get("accent")):
        colors["primary"] = accent
    if background := _hex(meta.get("background")):
        colors["surface"] = background
        colors["surfaceContainer"] = background
    return colors


def watched_paths() -> list[str]:
    """The files whose change should restyle the panel."""
    return [str(meta_path())]


def signature() -> tuple:
    """Cheap change detector: mtimes of everything that feeds the palette."""
    stamps = []
    for path in watched_paths():
        try:
            stamps.append(os.stat(path).st_mtime_ns)
        except OSError:
            stamps.append(0)
    return tuple(stamps)
