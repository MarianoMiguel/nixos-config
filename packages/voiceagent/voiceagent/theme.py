"""Follow the desktop's current colours.

The panel is a standalone quickshell surface, not a DankMaterialShell plugin,
so it cannot `import qs.Common` and read Theme directly. Resolving the palette
here instead keeps the chain -- settings -> custom theme file -> light or dark
variant -- in one testable place, and the panel just receives colours.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

log = logging.getLogger("voiceagent.theme")

# Used until DMS is readable, and for any role a theme omits. Deliberately
# neutral rather than pretty: if these show up, the theme lookup failed.
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

ROLES = tuple(FALLBACK)

# What DankMaterialShell rounds its own surfaces by, when nothing says otherwise.
FALLBACK_RADIUS = 12


def _config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(base) / "DankMaterialShell"


def _state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "DankMaterialShell"


def _read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def _radius_toggle() -> Path:
    """The file Mod+Ctrl+B rewrites.

    niri-style-toggle drops a `geometry-corner-radius 0` window rule in here to
    square everything off. That toggle is about windows, so it cannot reach a
    layer-shell surface like this panel -- following the file by hand is the
    only way the panel squares off along with everything else.
    """
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "nixos-config" / "dotfiles" / "niri" / "toggles" / "radius.kdl"


def theme_files() -> list[Path]:
    """Every file whose change should restyle the panel."""
    return [
        _config_dir() / "settings.json",
        _config_dir() / "theme.json",
        _state_dir() / "session.json",
        _radius_toggle(),
    ]


def radius() -> int:
    """Corner radius in pixels, 0 when rounding is toggled off."""
    try:
        if "geometry-corner-radius 0" in _radius_toggle().read_text():
            return 0
    except OSError:
        pass

    settings = _read_json(_config_dir() / "settings.json")
    value = settings.get("cornerRadius", FALLBACK_RADIUS)
    if isinstance(value, (int, float)) and value >= 0:
        return int(value)
    return FALLBACK_RADIUS


def resolve() -> dict[str, str]:
    """The colours DMS is currently drawing with."""
    settings = _read_json(_config_dir() / "settings.json")

    # A custom theme wins over the built-in one. This is how the themeport
    # palette reaches the shell, and the panel has to follow it.
    custom = settings.get("customThemeFile")
    source = Path(custom) if custom else _config_dir() / "theme.json"
    theme = _read_json(source)
    if not theme:
        theme = _read_json(_config_dir() / "theme.json")

    session = _read_json(_state_dir() / "session.json")
    variant = "light" if session.get("isLightMode") else "dark"
    palette = theme.get(variant) or theme.get("dark") or {}

    colors = dict(FALLBACK)
    for role in ROLES:
        value = palette.get(role)
        if isinstance(value, str) and value.startswith("#"):
            colors[role] = value
    return colors


def watched_paths() -> list[str]:
    """Existing theme files, for the daemon to poll for changes."""
    paths = list(theme_files())
    settings = _read_json(_config_dir() / "settings.json")
    if custom := settings.get("customThemeFile"):
        paths.append(Path(custom))
    return [str(path) for path in paths]


def signature() -> tuple:
    """Cheap change detector: mtimes of everything that feeds the palette."""
    stamps = []
    for path in watched_paths():
        try:
            stamps.append(os.stat(path).st_mtime_ns)
        except OSError:
            stamps.append(0)
    return tuple(stamps)
