#!/usr/bin/env python3
"""themeport — install Omarchy community themes on a Niri + DankMaterialShell system.

Pipeline: an Omarchy theme (colors.toml + optional per-app extras) is resolved
into the same color table Omarchy's own `omarchy-theme-color --all` produces,
then rendered through Omarchy's vendored *.tpl templates (byte-compatible
output) plus themeport's own targets (DMS theme JSON, tmux, browser policy).

The DMS theme is the linchpin: once DankMaterialShell adopts it, DMS's own
matugen cascade re-themes Niri, VS Code, Zed, Firefox and friends upstream of
us. themeport only fills the gaps DMS doesn't cover.

Stdlib only; Python >= 3.11 (tomllib). `render` is pure and runs anywhere;
`set`/`install` touch a live Linux system and are guarded.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
import tomllib
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATES_DIR = HERE / "templates" / "omarchy"

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
SAFE_THEME_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")

# ---------------------------------------------------------------- color utils


def _rgb(hexstr: str) -> tuple[int, int, int]:
    h = hexstr.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _hex(r: float, g: float, b: float) -> str:
    return "#%02x%02x%02x" % (round(r), round(g), round(b))


def mix(start: str, end: str, amount: float | str) -> str:
    """Port of Omarchy's mix_color: linear sRGB blend, amount 0..1 or '30%'."""
    if isinstance(amount, str):
        amount = float(amount.rstrip("%")) / 100 if amount.endswith("%") else float(amount)
    if amount > 1:
        amount = amount / 100
    amount = min(max(amount, 0.0), 1.0)
    sr, sg, sb = _rgb(start)
    er, eg, eb = _rgb(end)
    return _hex(
        sr * (1 - amount) + er * amount,
        sg * (1 - amount) + eg * amount,
        sb * (1 - amount) + eb * amount,
    )


def rel_luminance(hexstr: str) -> float:
    def chan(c: int) -> float:
        v = c / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = _rgb(hexstr)
    return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b)


def hex_to_rgb_str(hexstr: str) -> str:
    return "%d,%d,%d" % _rgb(hexstr)


# ------------------------------------------------------------ theme resolution

LEGACY_PALETTE_ALIAS = {
    "background": "bg",
    "dark_background": "dark_bg",
    "darker_background": "darker_bg",
    "lighter_background": "lighter_bg",
    "foreground": "fg",
    "dark_foreground": "dark_fg",
    "light_foreground": "light_fg",
    "bright_foreground": "bright_fg",
}

LEGACY_ANSI_ALIAS = {
    "red": "color1",
    "green": "color2",
    "yellow": "color3",
    "blue": "color4",
    "magenta": "color5",
    "cyan": "color6",
    "bright_red": "color9",
    "bright_green": "color10",
    "bright_yellow": "color11",
    "bright_blue": "color12",
    "bright_magenta": "color13",
    "bright_cyan": "color14",
}

ANSI_BACK_ALIAS = {
    "color0": "background",
    "color1": "red",
    "color2": "green",
    "color3": "yellow",
    "color4": "blue",
    "color5": "magenta",
    "color6": "cyan",
    "color7": "foreground",
    "color8": "muted",
    "color9": "bright_red",
    "color10": "bright_green",
    "color11": "bright_yellow",
    "color12": "bright_blue",
    "color13": "bright_magenta",
    "color14": "bright_cyan",
    "color15": "bright_foreground",
}


def _alias(colors: dict, key: str, fallback: str) -> None:
    if not colors.get(key) and colors.get(fallback):
        colors[key] = colors[fallback]


def resolve_colors(raw: dict[str, str], theme_dir: Path | None = None) -> dict[str, str]:
    """Port of omarchy-theme-color's resolve_theme_colors + resolve_theme_mode."""
    c = {k: str(v) for k, v in raw.items()}

    for key, fb in LEGACY_PALETTE_ALIAS.items():
        _alias(c, key, fb)

    _alias(c, "background", "color0")
    _alias(c, "foreground", "color7")
    if c.get("background"):
        c["color0"] = c["background"]
    if c.get("foreground"):
        c["color7"] = c["foreground"]

    for key, fb in LEGACY_ANSI_ALIAS.items():
        _alias(c, key, fb)
    _alias(c, "magenta", "purple")
    _alias(c, "bright_magenta", "bright_purple")

    c.setdefault("light_foreground", c.get("color7") or c.get("foreground", ""))
    c.setdefault("bright_foreground", c.get("color15") or c.get("foreground", ""))
    c["cursor"] = c["bright_foreground"]
    c.setdefault("lighter_background", c.get("color0") or c.get("background", ""))
    c.setdefault("dark_foreground", c.get("color8") or c.get("foreground", ""))
    c.setdefault("muted", c.get("color8") or c.get("dark_foreground", ""))
    if not c.get("selection"):
        c["selection"] = (
            c.get("selection_background")
            or c.get("color8")
            or c.get("color0")
            or c.get("background", "")
        )
    c.setdefault("selection_background", c["selection"])
    c.setdefault("selection_foreground", c["bright_foreground"])
    c.setdefault("orange", c.get("yellow", ""))
    if not c.get("brown") and HEX_RE.match(c.get("orange", "")):
        c["brown"] = mix(c["orange"], "#000000", "50%")

    bg = c.get("background", "")
    if not c.get("dark_background") and HEX_RE.match(bg):
        c["dark_background"] = mix(bg, "#000000", "25%")
    if not c.get("darker_background") and HEX_RE.match(bg):
        c["darker_background"] = mix(bg, "#000000", "50%")
    for name in ("red", "yellow", "green", "cyan", "blue", "magenta"):
        bright = f"bright_{name}"
        if not c.get(bright) and HEX_RE.match(c.get(name, "")):
            c[bright] = mix(c[name], "#ffffff", "20%")
    _alias(c, "purple", "magenta")
    _alias(c, "bright_purple", "bright_magenta")

    for key, fb in ANSI_BACK_ALIAS.items():
        _alias(c, key, fb)

    for key, short in LEGACY_PALETTE_ALIAS.items():
        if c.get(key):
            c[short] = c[key]

    # themeport addition: every consumer needs an accent; legacy themes lack one.
    c.setdefault("accent", c.get("blue", c.get("foreground", "")))

    # mode precedence: mode key, theme_type, light.mode file, luminance, dark
    if not c.get("mode"):
        c["mode"] = c.get("theme_type", "")
    if not c.get("mode"):
        if theme_dir is not None and (theme_dir / "light.mode").exists():
            c["mode"] = "light"
        elif HEX_RE.match(bg):
            r, g, b = _rgb(bg)
            c["mode"] = "light" if (r + g + b) > 382 else "dark"
        else:
            c["mode"] = "dark"
    c["theme_type"] = c["mode"]
    return c


# ----------------------------------------------------- legacy alacritty import

_ALACRITTY_COLOR_MAP = {
    "colors.primary.background": "background",
    "colors.primary.foreground": "foreground",
    "colors.cursor.cursor": "cursor",
    "colors.selection.background": "selection_background",
    "colors.selection.text": "selection_foreground",
    "colors.normal.black": "color0",
    "colors.normal.red": "red",
    "colors.normal.green": "green",
    "colors.normal.yellow": "yellow",
    "colors.normal.blue": "blue",
    "colors.normal.magenta": "magenta",
    "colors.normal.cyan": "cyan",
    "colors.normal.white": "color7",
    "colors.bright.black": "color8",
    "colors.bright.red": "bright_red",
    "colors.bright.green": "bright_green",
    "colors.bright.yellow": "bright_yellow",
    "colors.bright.blue": "bright_blue",
    "colors.bright.magenta": "bright_magenta",
    "colors.bright.cyan": "bright_cyan",
    "colors.bright.white": "bright_foreground",
}


def _norm_hex(value: str) -> str | None:
    value = value.strip().strip("\"'")
    if value.startswith("0x") and len(value) == 8:
        value = "#" + value[2:]
    return value if HEX_RE.match(value) else None


def colors_from_alacritty(path: Path) -> dict[str, str]:
    """Legacy pre-4.0 themes: derive the palette from the theme's alacritty.toml
    (same approach as Omarchy's omarchy-theme-colors-from-alacritty)."""
    data = tomllib.loads(path.read_text())
    flat: dict[str, str] = {}

    def walk(prefix: str, obj: object) -> None:
        if isinstance(obj, dict):
            for k, v in obj.items():
                walk(f"{prefix}.{k}" if prefix else str(k), v)
        elif isinstance(obj, str):
            flat[prefix] = obj

    walk("", data)
    raw: dict[str, str] = {}
    for dotted, semantic in _ALACRITTY_COLOR_MAP.items():
        if dotted in flat and (h := _norm_hex(flat[dotted])):
            raw.setdefault(semantic, h)
    return raw


# ------------------------------------------------------------------ theme load


class Theme:
    def __init__(self, name: str, colors: dict[str, str], src: Path):
        self.name = name
        self.colors = colors
        self.src = src
        self.mode = colors["mode"]
        self.vscode = self._load_json(src / "vscode.json")
        self.icons = self._read(src / "icons.theme")
        self.neovim = self._read(src / "neovim.lua")
        self.backgrounds = sorted(
            p.name
            for p in (src / "backgrounds").glob("*")
            if p.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")
        ) if (src / "backgrounds").is_dir() else []

    @staticmethod
    def _read(p: Path) -> str | None:
        return p.read_text().strip() if p.is_file() else None

    @staticmethod
    def _load_json(p: Path) -> dict | None:
        if not p.is_file():
            return None
        try:
            return json.loads(p.read_text())
        except json.JSONDecodeError:
            return None


def load_theme(theme_dir: Path) -> Theme:
    theme_dir = theme_dir.resolve()
    colors_file = theme_dir / "colors.toml"
    if colors_file.is_file():
        raw = {k: str(v) for k, v in tomllib.loads(colors_file.read_text()).items()}
    elif (theme_dir / "alacritty.toml").is_file():
        raw = colors_from_alacritty(theme_dir / "alacritty.toml")
    else:
        raise SystemExit(
            f"{theme_dir}: neither colors.toml (Omarchy >= 4) nor alacritty.toml "
            "(legacy theme) found — not an Omarchy theme?"
        )
    # Web protocol imports can carry a mode= override that takes precedence
    # over the downloaded colors.toml. Keep that transport-level decision in
    # sidecar metadata instead of rewriting the publisher's palette.
    mode_override = theme_dir / ".themeport-mode"
    if mode_override.is_file():
        mode = mode_override.read_text().strip()
        if mode not in ("dark", "light"):
            raise SystemExit(f"{mode_override}: expected 'dark' or 'light'")
        raw["mode"] = mode
    colors = resolve_colors(raw, theme_dir)
    missing = [k for k in ("background", "foreground", "red", "green", "blue") if not HEX_RE.match(colors.get(k, ""))]
    if missing:
        raise SystemExit(f"{theme_dir}: unusable palette, missing/invalid: {', '.join(missing)}")
    return Theme(theme_dir.name, colors, theme_dir)


# ------------------------------------------------------------ template engine

_TPL_TOKEN = re.compile(
    r"\{\{\s*(?:"
    r"(?P<mixfn>mix(?:_strip|_rgb)?)\s+(?P<m1>[A-Za-z0-9_]+)\s+(?P<m2>[A-Za-z0-9_]+)\s+(?P<amt>[0-9]+(?:\.[0-9]+)?%?)"
    r"|(?P<key>[A-Za-z0-9_]+?)(?P<suffix>_strip|_rgb)?"
    r")\s*\}\}"
)


def render_template(text: str, colors: dict[str, str]) -> str:
    unresolved: list[str] = []

    def sub(m: re.Match) -> str:
        if m.group("mixfn"):
            a, b = colors.get(m.group("m1"), ""), colors.get(m.group("m2"), "")
            if not (HEX_RE.match(a) and HEX_RE.match(b)):
                unresolved.append(m.group(0))
                return m.group(0)
            value = mix(a, b, m.group("amt"))
            if m.group("mixfn") == "mix_strip":
                return value[1:]
            if m.group("mixfn") == "mix_rgb":
                return hex_to_rgb_str(value)
            return value
        key, suffix = m.group("key"), m.group("suffix") or ""
        # suffix keys like foo_strip: the bare key is what carries the value
        value = colors.get(key)
        if value is None and suffix:
            unresolved.append(m.group(0))
            return m.group(0)
        if value is None:
            unresolved.append(m.group(0))
            return m.group(0)
        if suffix == "_strip":
            return value.lstrip("#")
        if suffix == "_rgb":
            return hex_to_rgb_str(value) if HEX_RE.match(value) else value
        return value

    out = _TPL_TOKEN.sub(sub, text)
    if unresolved:
        raise ValueError(f"unresolved template tokens: {sorted(set(unresolved))}")
    return out


# ------------------------------------------------------------- DMS theme JSON


def _on_color(color: str, colors: dict[str, str], mode: str) -> str:
    if rel_luminance(color) > 0.45:
        return colors["darker_background"] if mode == "dark" else mix(color, "#000000", 0.8)
    return "#ffffff" if mode == "light" else colors["bright_foreground"]


def _pick_distinct(colors: dict[str, str], avoid: set[str], candidates: list[str]) -> str:
    for name in candidates:
        value = colors.get(name, "")
        if HEX_RE.match(value) and value.lower() not in avoid:
            return value
    return colors["foreground"]


def dms_variant(colors: dict[str, str], label: str) -> dict[str, str]:
    mode = colors["mode"]
    bg, fg = colors["background"], colors["foreground"]
    accent = colors["accent"] if HEX_RE.match(colors.get("accent", "")) else colors["blue"]
    taken = {accent.lower()}
    secondary = _pick_distinct(colors, taken, ["blue", "cyan", "magenta", "green", "yellow"])
    taken.add(secondary.lower())
    tertiary = _pick_distinct(colors, taken, ["green", "magenta", "cyan", "yellow", "orange"])
    taken.add(tertiary.lower())
    info = _pick_distinct(colors, taken, ["cyan", "blue", "magenta"])

    lighter, dark_bg, darker = (
        colors["lighter_background"],
        colors["dark_background"],
        colors["darker_background"],
    )
    if mode == "dark":
        elevation = {
            "surfaceContainerLowest": darker,
            "surfaceContainerLow": mix(bg, lighter, 0.3),
            "surfaceContainer": mix(bg, lighter, 0.6),
            "surfaceContainerHigh": lighter,
            "surfaceContainerHighest": mix(lighter, "#ffffff", 0.06),
        }
    else:
        elevation = {
            "surfaceContainerLowest": mix(bg, "#ffffff", 0.6),
            "surfaceContainerLow": mix(bg, dark_bg, 0.35),
            "surfaceContainer": mix(bg, dark_bg, 0.6),
            "surfaceContainerHigh": dark_bg,
            "surfaceContainerHighest": darker,
        }

    def container(color: str) -> str:
        return mix(color, bg, 0.68)

    def container_text(color: str) -> str:
        return mix(color, "#ffffff" if mode == "dark" else "#000000", 0.55)

    variant = {
        "name": label,
        "primary": accent,
        "primaryText": _on_color(accent, colors, mode),
        "primaryContainer": container(accent),
        "primaryContainerText": container_text(accent),
        "secondary": secondary,
        "secondaryText": _on_color(secondary, colors, mode),
        "secondaryContainer": container(secondary),
        "secondaryContainerText": container_text(secondary),
        "tertiary": tertiary,
        "tertiaryText": _on_color(tertiary, colors, mode),
        "tertiaryContainer": container(tertiary),
        "tertiaryContainerText": container_text(tertiary),
        "surface": bg,
        "surfaceText": fg,
        "surfaceVariant": lighter,
        "surfaceVariantText": colors["dark_foreground"],
        "surfaceTint": accent,
        "background": bg,
        "backgroundText": fg,
        "outline": colors["muted"],
        "outlineVariant": colors["selection"],
        **elevation,
        "error": colors["red"],
        "warning": colors["orange"],
        "info": info,
    }
    return variant


def build_dms_theme(theme: Theme, other: Theme | None) -> dict:
    """One DMS theme with dark+light slots. Unpaired themes mirror their palette
    into both slots (matching how Omarchy treats theme==mode)."""
    slots: dict[str, Theme] = {theme.mode: theme}
    if other is not None:
        if other.mode == theme.mode:
            raise SystemExit(
                f"--pair theme '{other.name}' has the same mode ({other.mode}) as '{theme.name}'"
            )
        slots[other.mode] = other
    dark = slots.get("dark", theme)
    light = slots.get("light", theme)
    pretty = theme.name.replace("-", " ").title()
    return {
        "id": f"themeport-{theme.name}",
        "name": pretty,
        "version": "1.0.0",
        "author": "themeport (from Omarchy community themes)",
        "description": f"Converted from the Omarchy theme '{theme.name}'"
        + (f" paired with '{other.name}'" if other else ""),
        "dark": dms_variant(dark.colors, f"{pretty} Dark" if other or dark.mode == "dark" else pretty),
        "light": dms_variant(light.colors, f"{pretty} Light" if other or light.mode == "light" else pretty),
    }


# ------------------------------------------------------------------ renderers


def render_browser_policy(colors: dict[str, str]) -> str:
    return json.dumps({"BrowserThemeColor": colors["background"]}, indent=2) + "\n"


def render_tmux(colors: dict[str, str]) -> str:
    c = colors
    return f"""# themeport tmux colors (sourced from tmux.conf)
set -g status-style "bg={c['dark_background']},fg={c['foreground']}"
set -g status-left-style "bg={c['accent']},fg={c['background']}"
set -g window-status-current-style "bg={c['selection']},fg={c['bright_foreground']},bold"
set -g window-status-style "bg=default,fg={c['dark_foreground']}"
set -g pane-border-style "fg={c['selection']}"
set -g pane-active-border-style "fg={c['accent']}"
set -g message-style "bg={c['selection']},fg={c['bright_foreground']}"
set -g mode-style "bg={c['selection_background']},fg={c['selection_foreground']}"
set -g copy-mode-match-style "bg={c['yellow']},fg={c['background']}"
set -g copy-mode-current-match-style "bg={c['red']},fg={c['background']}"
"""


def render_vicinae_theme(theme: Theme) -> str:
    """Render Vicinae's native TOML theme from the same resolved palette.

    Keeping this as a custom theme (rather than an opacity or GTK override)
    lets Vicinae retain its own interaction design while matching every
    Themeport switch immediately.
    """
    c = theme.colors
    accent = c["accent"]
    accent_foreground = _on_color(accent, c, theme.mode)
    inherits = "vicinae-light" if theme.mode == "light" else "vicinae-dark"
    pretty = theme.name.replace("-", " ").title()
    return f'''[meta]
version = 1
name = "Themeport · {pretty}"
description = "Generated from the active Themeport palette"
variant = "{theme.mode}"
inherits = "{inherits}"

[colors.core]
accent = "{accent}"
accent_foreground = "{accent_foreground}"
background = "{c['background']}"
foreground = "{c['foreground']}"
secondary_background = "{c['lighter_background']}"
border = "{c['selection']}"

[colors.main_window]
border = "{c['selection']}"
footer = {{ background = "colors.core.secondary_background" }}

[colors.settings_window]
border = "{c['selection']}"

[colors.accents]
blue = "{c['blue']}"
green = "{c['green']}"
magenta = "{c['magenta']}"
orange = "{c['orange']}"
red = "{c['red']}"
yellow = "{c['yellow']}"
cyan = "{c['cyan']}"
purple = "{c['purple']}"

[colors.shortcut]
border = "colors.core.border"

[colors.text]
default = "colors.core.foreground"
muted = "{c['dark_foreground']}"
danger = "{c['red']}"
success = "{c['green']}"
placeholder = "{c['muted']}"
selection = {{ background = "{accent}", foreground = "{accent_foreground}" }}

[colors.text.links]
default = "{c['blue']}"
visited = "{c['magenta']}"

[colors.input]
border = "{c['selection']}"
border_focus = "{accent}"
border_error = "{c['red']}"

[colors.button.primary]
background = "{c['lighter_background']}"
foreground = "{c['foreground']}"
focus = {{ outline = "colors.core.accent" }}

[colors.list.item.hover]
foreground = "{c['bright_foreground']}"
secondary_foreground = "{c['foreground']}"

[colors.list.item.selection]
background = "{c['selection_background']}"
foreground = "{c['selection_foreground']}"
secondary_background = "{c['lighter_background']}"
secondary_foreground = "{c['foreground']}"

[colors.grid.item]
background = "{c['lighter_background']}"
hover = {{ outline = "{accent}" }}
selection = {{ outline = "{c['bright_foreground']}" }}

[colors.scrollbars]
background = "{c['selection']}"

[colors.loading]
bar = "{accent}"
spinner = "{c['foreground']}"
'''


TPL_OUTPUTS = {
    # template file -> output path (relative to render dir)
    "ghostty.conf.tpl": "ghostty/themes/themeport",
    "alacritty.toml.tpl": "alacritty/themeport.toml",
    "btop.theme.tpl": "btop/themes/themeport.theme",
    "vscode-theme.json.tpl": "vscode/themeport-color-theme.json",
    "neovim.lua.tpl": "neovim/generated.lua",
    "obsidian.css.tpl": "obsidian/themeport.css",
}


def render_all(theme: Theme, other: Theme | None) -> dict[str, str]:
    out: dict[str, str] = {}
    out["dms/theme.json"] = json.dumps(build_dms_theme(theme, other), indent=2) + "\n"

    for tpl_name, rel in TPL_OUTPUTS.items():
        tpl_path = TEMPLATES_DIR / tpl_name
        if not tpl_path.is_file():
            continue
        out[rel] = render_template(tpl_path.read_text(), theme.colors)

    out["chrome/color.json"] = render_browser_policy(theme.colors)
    out["tmux/themeport.conf"] = render_tmux(theme.colors)
    out["vicinae/themeport.toml"] = render_vicinae_theme(theme)

    if theme.neovim:
        out["neovim/theme.lua"] = theme.neovim + "\n"

    meta = {
        "name": theme.name,
        "mode": theme.mode,
        "icons": theme.icons,
        "vscode": theme.vscode,
        "has_theme_neovim": theme.neovim is not None,
        "backgrounds": theme.backgrounds,
        "paired_with": other.name if other else None,
        "accent": theme.colors["accent"],
        "background": theme.colors["background"],
    }
    out["meta.json"] = json.dumps(meta, indent=2) + "\n"
    return out


# --------------------------------------------------------------- theme store


def themes_home() -> Path:
    if env := os.environ.get("THEMEPORT_HOME"):
        return Path(env)
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "themeport/themes"


def normalize_theme_name(repo_name: str) -> str:
    name = repo_name.lower()
    name = re.sub(r"^omarchy[-_]", "", name)
    name = re.sub(r"[-_]theme$", "", name)
    return name or repo_name.lower()


def parse_repo_ref(ref: str) -> tuple[str, str]:
    """Accept 'owner/repo', a full GitHub URL, or 'github:owner/repo'."""
    ref = ref.removeprefix("github:")
    m = re.match(r"^(?:https?://github\.com/)?([\w.-]+)/([\w.-]+?)(?:\.git)?/?$", ref)
    if not m:
        raise SystemExit(f"can't parse theme source {ref!r}: expected owner/repo or a GitHub URL")
    return m.group(1), m.group(2)


def find_theme_root(extracted: Path) -> Path:
    """The theme payload may sit at the repo root or one level down."""
    if (extracted / "colors.toml").is_file() or (extracted / "alacritty.toml").is_file():
        return extracted
    candidates = [
        d for d in sorted(extracted.iterdir())
        if d.is_dir() and ((d / "colors.toml").is_file() or (d / "alacritty.toml").is_file())
    ]
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise SystemExit(f"no colors.toml/alacritty.toml found anywhere under {extracted}")
    raise SystemExit(
        f"multiple theme dirs found under {extracted}: {[c.name for c in candidates]} — "
        "install the specific subdirectory instead"
    )


def install_from_github(ref: str, dest_root: Path) -> Path:
    owner, repo = parse_repo_ref(ref)
    url = f"https://codeload.github.com/{owner}/{repo}/tar.gz/HEAD"
    print(f"fetching {owner}/{repo} ...")
    with urllib.request.urlopen(url, timeout=60) as resp:  # noqa: S310
        data = resp.read()

    name = normalize_theme_name(repo)
    dest = dest_root / name
    staging = dest_root / f".staging-{name}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        tar.extractall(staging, filter="data")
    # tarball wraps everything in <repo>-<sha>/
    wrapper = next(d for d in staging.iterdir() if d.is_dir())
    root = find_theme_root(wrapper)

    load_theme(root)  # validate before committing to the store

    if dest.exists():
        shutil.rmtree(dest)
    shutil.move(str(root), str(dest))
    shutil.rmtree(staging, ignore_errors=True)
    (dest / ".themeport-source").write_text(f"{owner}/{repo}\n")
    return dest


# --------------------------------------------------------- Aether web adapter


def validate_theme_name(name: str) -> str:
    if not SAFE_THEME_NAME_RE.fullmatch(name):
        raise SystemExit(
            f"invalid theme name {name!r}: expected 1-64 letters, numbers, dots, dashes or underscores"
        )
    return name


def _validated_https_url(value: str, label: str) -> str:
    """Accept only public-looking HTTPS URLs for browser-triggered imports."""
    if any(char in value for char in "\r\n\t"):
        raise SystemExit(f"{label} URL contains control characters")
    value = value.replace(" ", "%20")
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise SystemExit(f"invalid {label} URL: {exc}") from exc
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        raise SystemExit(f"{label} must be an https:// URL")
    if parsed.username is not None or parsed.password is not None:
        raise SystemExit(f"{label} URL must not contain credentials")
    host = parsed.hostname.rstrip(".").lower()
    if host == "localhost" or host.endswith(".localhost"):
        raise SystemExit(f"{label} URL must not target localhost")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise SystemExit(f"{label} URL must not target a private or local address")
    if port is not None and not (1 <= port <= 65535):
        raise SystemExit(f"invalid {label} URL port")
    return urllib.parse.urlunsplit(parsed)


def _download_https(url: str, max_bytes: int) -> tuple[bytes, str, str]:
    """Download one bounded HTTPS resource and re-check any redirect target."""
    url = _validated_https_url(url, "download")
    req = urllib.request.Request(url, headers={"User-Agent": "themeport/0.2"})  # noqa: S310
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310
        final_url = _validated_https_url(resp.geturl(), "redirect target")
        length = resp.headers.get("Content-Length")
        if length and int(length) > max_bytes:
            raise SystemExit(f"download is too large ({int(length)} bytes; limit {max_bytes})")
        data = resp.read(max_bytes + 1)
        if len(data) > max_bytes:
            raise SystemExit(f"download exceeded the {max_bytes}-byte limit")
        content_type = resp.headers.get_content_type().lower()
    return data, content_type, final_url


def _image_extension(data: bytes, content_type: str) -> str:
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"
    raise SystemExit(
        f"wallpaper is not a supported JPEG, PNG or WebP image (content-type {content_type!r})"
    )


def install_from_aether_urls(
    name: str,
    colors_url: str,
    wallpaper_url: str | None,
    dest_root: Path,
    *,
    mode: str | None = None,
    source_label: str | None = None,
    downloader=None,
) -> Path:
    """Turn the transport-neutral part of an aether:// link into an Omarchy
    theme directory that the existing ThemePort renderer can consume."""
    name = validate_theme_name(name)
    colors_url = _validated_https_url(colors_url, "colors")
    if wallpaper_url:
        wallpaper_url = _validated_https_url(wallpaper_url, "wallpaper")
    if mode not in (None, "dark", "light"):
        raise SystemExit("mode must be 'dark' or 'light'")

    fetch = downloader or _download_https
    dest = dest_root / name
    staging = dest_root / f".staging-{name}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    try:
        colors_data, _colors_type, final_colors_url = fetch(colors_url, 256 * 1024)
        try:
            colors_text = colors_data.decode("utf-8-sig")
            tomllib.loads(colors_text)
        except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
            raise SystemExit(f"downloaded colors file is not valid UTF-8 TOML: {exc}") from exc
        (staging / "colors.toml").write_text(colors_text)

        final_wallpaper_url = None
        if wallpaper_url:
            wallpaper_data, wallpaper_type, final_wallpaper_url = fetch(
                wallpaper_url, 64 * 1024 * 1024
            )
            suffix = _image_extension(wallpaper_data, wallpaper_type)
            raw_name = Path(urllib.parse.unquote(urllib.parse.urlsplit(wallpaper_url).path)).stem
            base_name = re.sub(r"[^A-Za-z0-9._-]+", "-", raw_name).strip(".-")[:96]
            filename = f"{base_name or 'wallpaper'}{suffix}"
            backgrounds = staging / "backgrounds"
            backgrounds.mkdir()
            (backgrounds / filename).write_bytes(wallpaper_data)

        if mode:
            (staging / ".themeport-mode").write_text(f"{mode}\n")
        metadata = {
            "protocol": "aether://apply",
            "colors": final_colors_url,
            "wallpaper": final_wallpaper_url,
            "mode": mode,
        }
        (staging / ".themeport-import.json").write_text(json.dumps(metadata, indent=2) + "\n")
        (staging / ".themeport-source").write_text(
            f"{source_label or 'aether:' + urllib.parse.urlsplit(colors_url).hostname}\n"
        )

        load_theme(staging)  # validate the complete bundle before replacing anything
        if dest.exists():
            shutil.rmtree(dest)
        shutil.move(str(staging), str(dest))
        return dest
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def parse_aether_apply_url(raw_url: str) -> dict[str, object]:
    """Parse the supported, safe subset of Aether's published web contract."""
    if len(raw_url) > 16 * 1024:
        raise SystemExit("aether URL is too long")
    parsed = urllib.parse.urlsplit(raw_url)
    if parsed.scheme.lower() != "aether" or parsed.netloc.lower() != "apply" or parsed.path not in ("", "/"):
        raise SystemExit("expected an aether://apply?... URL")

    params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
    supported = {
        "external_theme", "colors", "wallpaper", "mode", "silent", "edit", "as_omarchy_theme"
    }
    unknown = sorted(set(params) - supported)
    if unknown:
        raise SystemExit(f"unsupported aether parameter(s): {', '.join(unknown)}")
    duplicates = sorted(key for key, values in params.items() if len(values) != 1)
    if duplicates:
        raise SystemExit(f"duplicate aether parameter(s): {', '.join(duplicates)}")

    def one(key: str) -> str | None:
        values = params.get(key)
        return values[0] if values else None

    if one("external_theme"):
        raise SystemExit("Aether blueprint JSON is not supported; use a colors.toml link")
    edit = one("edit")
    silent = one("silent")
    for key, value in (("edit", edit), ("silent", silent)):
        if value not in (None, "true", "false"):
            raise SystemExit(f"{key} must be 'true' or 'false'")
    if edit == "true":
        raise SystemExit("ThemePort has no palette editor; choose the gallery's Apply action instead")

    colors = one("colors")
    if not colors:
        raise SystemExit("this adapter requires a colors=https://... parameter")
    colors = _validated_https_url(colors, "colors")
    wallpaper = one("wallpaper")
    if wallpaper:
        wallpaper = _validated_https_url(wallpaper, "wallpaper")

    mode = one("mode")
    if mode not in (None, "dark", "light"):
        raise SystemExit("mode must be 'dark' or 'light'")
    name = one("as_omarchy_theme")
    if not name:
        parent = Path(urllib.parse.unquote(urllib.parse.urlsplit(colors).path)).parent.name
        name = normalize_theme_name(parent or "web-theme")
    name = validate_theme_name(name)
    return {
        "name": name,
        "colors": colors,
        "wallpaper": wallpaper,
        "mode": mode,
        # Deliberately informational: browser-dispatched imports always prompt.
        "requested_silent": silent == "true" or one("as_omarchy_theme") is not None,
    }


# ------------------------------------------------------------------------ CLI


def cmd_render(args: argparse.Namespace) -> int:
    theme = load_theme(Path(args.theme_dir))
    other = load_theme(Path(args.pair)) if args.pair else None
    outdir = Path(args.output)
    files = render_all(theme, other)
    for rel, content in files.items():
        dest = outdir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
    print(f"rendered {len(files)} files for '{theme.name}' ({theme.mode}) -> {outdir}")
    return 0


# ----------------------------------------------------------------- apply/set


def xdg_state_home() -> Path:
    if env := os.environ.get("XDG_STATE_HOME"):
        return Path(env)
    return Path.home() / ".local/state"


def xdg_config_home() -> Path:
    if env := os.environ.get("XDG_CONFIG_HOME"):
        return Path(env)
    return Path.home() / ".config"


def state_root() -> Path:
    if env := os.environ.get("THEMEPORT_STATE"):
        return Path(env)
    return xdg_state_home() / "nixos-config/dotfiles/themeport"


def _run_quiet(cmd: list[str]) -> bool:
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=30)
        return True
    except Exception:  # noqa: BLE001
        return False


def _dms_ipc(*args: str, timeout: int = 10) -> str | None:
    """Call `dms ipc call ...`; stdout (stripped) on success, None on failure."""
    if not shutil.which("dms"):
        return None
    try:
        proc = subprocess.run(
            ["dms", "ipc", "call", *args], capture_output=True, text=True, timeout=timeout
        )
    except Exception:  # noqa: BLE001
        return None
    return proc.stdout.strip() if proc.returncode == 0 else None


def _dms_get(key: str) -> object | None:
    out = _dms_ipc("settings", "get", key)
    if out is None:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return out


def _dms_set(key: str, value: object) -> bool:
    out = _dms_ipc("settings", "set", key, str(value))
    return out is not None and "SUCCESS" in out


def _edit_json(path: Path, updates: dict) -> bool:
    """Merge keys into a JSON file, preserving everything else."""
    try:
        data = json.loads(path.read_text()) if path.is_file() else {}
    except json.JSONDecodeError:
        print(f"  ! {path} is not valid JSON — skipped ({', '.join(updates)})")
        return False
    data.update(updates)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    return True


# matugen cascade output we can observe to confirm DMS actually re-themed
NIRI_COLORS = Path.home() / ".config/niri/dms/colors.kdl"


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _wait_newer(path: Path, baseline: float, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _mtime(path) > baseline:
            return True
        time.sleep(0.3)
    return False


def apply_dms(state: Path, meta: dict, restart_ok: bool = True) -> bool:
    """Apply the theme to DMS, live when possible. Returns True if a running
    shell took it (so later steps may rely on the IPC socket being up).

    A restart is the exception, not the rule: DMS watches the custom theme
    file and reloads it — including the matugen cascade that re-themes niri,
    nvim, ghostty & co. Restarting right after writing the file used to kill
    the (100ms-debounced) cascade before it ran, and on startup the cascade
    loses a race against DMS's async matugen check, so custom themes came up
    with stale niri/nvim colors.
    """
    dms_config = xdg_config_home() / "DankMaterialShell"
    theme_path = dms_config / "themes/themeport/theme.json"
    desired = {
        "currentThemeCategory": "custom",
        "currentThemeName": "custom",
        "customThemeFile": str(theme_path),
    }
    icons = {}
    if meta.get("icons"):
        icons = {"iconThemeDark": meta["icons"], "iconThemeLight": meta["icons"]}

    if _dms_get("currentThemeName") is None:
        # shell not reachable: stage everything on disk for its next start
        if _edit_json(dms_config / "settings.json", {**desired, **icons}):
            print("  dms: not running — settings staged for next start")
        theme_doc = json.loads((state / "dms/theme.json").read_text())
        live_doc = {"name": theme_doc["name"], "dark": theme_doc["dark"], "light": theme_doc["light"]}
        (dms_config / "theme.json").write_text(json.dumps(live_doc, indent=2) + "\n")
        return False

    # `settings set` both applies live and persists via DMS itself, so we never
    # race the shell's own settings writes.
    needs_repoint = any(_dms_get(k) != v for k, v in desired.items())
    for key, value in {**desired, **icons}.items():
        if _dms_get(key) != value and not _dms_set(key, value):
            print(f"  ! dms: couldn't set {key}")

    if needs_repoint:
        # Theme.qml doesn't react to customThemeFile changing under it and IPC
        # can't invoke switchTheme, so adopting the themeport slot from another
        # theme needs one restart. The cascade re-trigger below papers over the
        # startup race.
        if not (restart_ok and shutil.which("systemctl")
                and _run_quiet(["systemctl", "--user", "restart", "dms.service"])):
            print("  ! dms: theme repoint pending — run: systemctl --user restart dms.service")
            return False
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and _dms_get("currentThemeName") is None:
            time.sleep(0.5)
        print("  dms: restarted to adopt the themeport theme slot")

    # match the shell's light/dark mode to the theme before it renders
    _dms_ipc("theme", meta["mode"])

    # (Re)write the watched theme file now that settings are in place; the
    # FileView watcher reloads it and kicks off the matugen cascade. Verify by
    # watching the cascade's niri output; one rewrite retry covers a missed
    # watch event.
    theme_json = (state / "dms/theme.json").read_text()
    baseline = _mtime(NIRI_COLORS)
    for _attempt in range(2):
        theme_path.write_text(theme_json)
        if not NIRI_COLORS.exists() or _wait_newer(NIRI_COLORS, baseline, timeout=6.0):
            break
    else:
        print("  ! dms: matugen cascade didn't regenerate niri colors — check: journalctl --user -u dms")
    print(f"  dms: theme applied live -> {meta['name']}")
    return True


def apply_mode(meta: dict) -> None:
    scheme = "prefer-dark" if meta["mode"] == "dark" else "prefer-light"
    if shutil.which("gsettings") and _run_quiet(
        ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme]
    ):
        print(f"  portal: color-scheme -> {scheme}")


def apply_icons(meta: dict) -> None:
    name = meta.get("icons")
    if not name:
        return
    candidates = [
        Path("/run/current-system/sw/share/icons") / name,
        Path.home() / ".nix-profile/share/icons" / name,
        Path("/usr/share/icons") / name,
        Path.home() / ".local/share/icons" / name,
    ]
    if not any(p.is_dir() for p in candidates):
        print(f"  ! icon theme '{name}' not installed — themeport.nix ships the Yaru set; rebuild if missing")
        return
    if shutil.which("gsettings"):
        _run_quiet(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", name])
    print(f"  icons: {name}")


def apply_wallpapers(theme: Theme, meta: dict) -> None:
    if not theme.backgrounds:
        return
    wallpaper_root = Path.home() / "Pictures/Wallpapers"
    canonical = [wallpaper_root / f"{theme.name}--{bg}" for bg in theme.backgrounds]
    if all(path.is_file() for path in canonical):
        first = canonical[0]
        location = f"{len(canonical)} available in the shared library"
    else:
        # Custom/legacy themes are not part of the declarative catalog. Keep a
        # writable fallback for them without affecting the reviewed flat set.
        dest = wallpaper_root / "themeport" / theme.name
        dest.mkdir(parents=True, exist_ok=True)
        for bg in theme.backgrounds:
            shutil.copy2(theme.src / "backgrounds" / bg, dest / bg)
        first = dest / theme.backgrounds[0]
        location = f"{len(theme.backgrounds)} copied"
    if _dms_ipc("wallpaper", "set", str(first), timeout=15) is not None:
        print(f"  wallpaper: {first.name} ({location})")
    elif _edit_json(
        xdg_state_home() / "DankMaterialShell/session.json",
        {"wallpaperPath": str(first)},
    ):
        # shell not reachable: stage it in session state for the next start
        print(f"  wallpaper: staged {first.name} for next DMS start ({location})")
    else:
        print(f"  wallpaper: {location} (set one via the DMS settings UI)")


def _edit_jsonc_string_key(path: Path, key: str, value: str) -> bool:
    """Set one top-level string key in a JSONC file. VS Code settings allow
    comments and trailing commas, so json.loads chokes on them (which used to
    silently skip the theme switch); edit the text in place instead."""
    text = path.read_text() if path.is_file() else "{}\n"
    encoded = json.dumps(value)
    pattern = re.compile(r'("' + re.escape(key) + r'"\s*:\s*)"(?:[^"\\]|\\.)*"')
    if pattern.search(text):
        new_text = pattern.sub(lambda m: m.group(1) + encoded, text, count=1)
    else:
        brace = text.rfind("}")
        if brace == -1:
            print(f"  ! {path}: no top-level object — skipped {key}")
            return False
        head = text[:brace].rstrip()
        sep = "" if head.endswith(("{", ",")) else ","
        new_text = f'{head}{sep}\n  "{key}": {encoded}\n{text[brace:]}'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_text)
    return True


def _build_local_vsix(state: Path, meta: dict, out: Path) -> None:
    """Pack the generated color theme as a minimal .vsix. Modern VS Code only
    loads extensions listed in its registry, so a folder dropped into
    ~/.vscode/extensions is ignored — `code --install-extension x.vsix` is the
    supported route."""
    import zipfile

    package = {
        "name": "themeport-theme",
        "displayName": "Themeport",
        "publisher": "themeport",
        "version": "1.0.0",
        "engines": {"vscode": "^1.60.0"},
        "categories": ["Themes"],
        "contributes": {"themes": [{
            "label": "Themeport",
            "uiTheme": "vs-dark" if meta["mode"] == "dark" else "vs",
            "path": "./themes/themeport-color-theme.json",
        }]},
    }
    manifest = """<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="themeport-theme" Version="1.0.0" Publisher="themeport"/>
    <DisplayName>Themeport</DisplayName>
    <Description>Color theme generated by themeport</Description>
    <Categories>Themes</Categories>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
"""
    content_types = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json"/>
  <Default Extension="vsixmanifest" ContentType="text/xml"/>
</Types>
"""
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("extension.vsixmanifest", manifest)
        z.writestr("extension/package.json", json.dumps(package, indent=2) + "\n")
        z.writestr(
            "extension/themes/themeport-color-theme.json",
            (state / "vscode/themeport-color-theme.json").read_text(),
        )


def apply_vscode(state: Path, meta: dict) -> None:
    settings = xdg_config_home() / "Code/User/settings.json"
    vscode = meta.get("vscode") or {}
    ext, label = vscode.get("extension"), vscode.get("name")
    editor = shutil.which("code") or shutil.which("codium")

    if ext and editor:
        if _run_quiet([editor, "--install-extension", ext]):
            print(f"  vscode: installed {ext}")
        else:
            print(f"  ! vscode: could not install {ext} — theme may not apply until you install it")
    if not (ext and label):
        label = "Themeport"
        if editor:
            vsix = _catalog_cache().parent / "themeport.vsix"
            _build_local_vsix(state, meta, vsix)
            # --force: the version is always 1.0.0 but the palette changes
            if _run_quiet([editor, "--install-extension", str(vsix), "--force"]):
                print("  vscode: installed generated theme (.vsix)")
            else:
                print("  ! vscode: could not install the generated theme .vsix")
        else:
            print("  ! vscode: no code/codium CLI — can't install the generated theme")
    if _edit_jsonc_string_key(settings, "workbench.colorTheme", label):
        print(f"  vscode: colorTheme -> {label} (open windows need a reload to notice)")


# exe -> process comm name. NixOS wrappers exec the real binary, so neither
# comm nor cmdline contains the wrapper name (chrome's comm is just "chrome");
# pgrep on the exe name can never match.
BROWSERS = {"google-chrome-stable": "chrome", "brave": "brave"}


def apply_browsers(meta: dict) -> None:
    # A root systemd service validates the user-rendered request and publishes
    # only BrowserThemeColor as managed policy.  Wait briefly for that bridge
    # so a live refresh can never race and re-apply the previous theme.
    policy = Path("/etc/opt/chrome/policies/managed/themeport-color.json")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            if json.loads(policy.read_text()).get("BrowserThemeColor") == meta["background"]:
                break
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    else:
        print("  ! chrome: validated policy did not update — check themeport-chrome-policy.service")
        return

    for exe, comm in BROWSERS.items():
        if not shutil.which(exe):
            continue
        if not _run_quiet(["pgrep", "-x", comm]):
            continue  # not running: the policy file applies on next launch
        if _run_quiet([exe, "--refresh-platform-policy", "--no-startup-window"]):
            print(f"  {exe}: policy refreshed live")
        else:
            print(f"  ! {exe}: policy refresh failed — restart the browser to apply")


def apply_vicinae() -> None:
    if not shutil.which("vicinae"):
        return
    if _run_quiet(["vicinae", "theme", "set", "themeport"]):
        print("  vicinae: active launcher palette updated")
    else:
        print("  ! vicinae: theme staged; restart Vicinae if it did not update live")


def apply_terminals() -> None:
    if shutil.which("tmux") and _run_quiet(["tmux", "has-session"]):
        conf = Path.home() / ".config/tmux/themeport.conf"
        if _run_quiet(["tmux", "source-file", str(conf)]):
            print("  tmux: reloaded")
    # alacritty live-reloads its import on write; ghostty needs a nudge
    print("  ghostty: existing windows need reload_config (ctrl+shift+,) — new windows pick it up")


def apply_btop() -> None:
    conf = Path.home() / ".config/btop/btop.conf"
    line = 'color_theme = "themeport"'
    if conf.is_file():
        text = conf.read_text()
        if re.search(r"^color_theme\s*=.*$", text, flags=re.M):
            text = re.sub(r"^color_theme\s*=.*$", line, text, flags=re.M)
        else:
            text += f"\n{line}\n"
    else:
        conf.parent.mkdir(parents=True, exist_ok=True)
        text = line + "\n"
    conf.write_text(text)
    print("  btop: theme set (applies on next start)")


def cmd_set(args: argparse.Namespace) -> int:
    store = themes_home()
    theme_dir = Path(args.name) if os.sep in args.name else store / args.name
    if not theme_dir.exists():
        raise SystemExit(f"theme '{args.name}' not found — install it first (themeport install owner/repo)")
    theme = load_theme(theme_dir)
    other = None
    if args.pair:
        pair_dir = Path(args.pair) if os.sep in args.pair else store / args.pair
        other = load_theme(pair_dir)

    state = state_root()
    state.mkdir(parents=True, exist_ok=True)

    files = render_all(theme, other)
    for rel, content in files.items():
        dest = state / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
    meta = json.loads(files["meta.json"])
    print(f"applying '{theme.name}' ({theme.mode}){f' + {other.name}' if other else ''}:")

    apply_mode(meta)
    apply_icons(meta)
    apply_dms(state, meta, restart_ok=not getattr(args, "no_restart", False))
    apply_wallpapers(theme, meta)
    apply_vscode(state, meta)
    apply_browsers(meta)
    apply_vicinae()
    apply_terminals()
    apply_btop()
    print(f"done. rendered state lives in {state}")
    return 0


# ------------------------------------------------------------ online catalog

CATALOG_TTL = 24 * 3600
OMARCHY_REPO = "basecamp/omarchy"
OMARCHY_REF = "quattro"
AETHER_GALLERY_INDEX = "https://bjarneo.github.io/omarchy-themes/wallpapers.js"
AETHER_VARIANT_ORDER = ("palette", "gruvbox", "nord", "material", "aether")
AETHER_VARIANT_LABELS = {
    "palette": "Palette",
    "gruvbox": "Warm",
    "nord": "Cool",
    "material": "Material",
    "aether": "Aether",
}
AETHER_SWATCH_KEYS = (
    "background", "accent", "red", "yellow", "green", "cyan", "blue", "magenta"
)


def _gh_token() -> str | None:
    if token := os.environ.get("GITHUB_TOKEN"):
        return token
    if shutil.which("gh"):
        try:
            out = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=10)
            return out.stdout.strip() or None
        except Exception:  # noqa: BLE001
            return None
    return None


def _github_json(url: str) -> object:
    req = urllib.request.Request(  # noqa: S310
        url, headers={"Accept": "application/vnd.github+json", "User-Agent": "themeport"}
    )
    if token := _gh_token():
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310
        return json.loads(resp.read())


def _catalog_cache() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "themeport/catalog.json"


def _aether_catalog_cache() -> Path:
    return _catalog_cache().parent / "aether-gallery.json"


def _parse_aether_gallery_script(data: bytes) -> tuple[str, dict]:
    try:
        script = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SystemExit(f"Omarchy Themes index is not UTF-8: {exc}") from exc
    base_match = re.search(r"window\.WALLPAPERS_BASE_URL\s*=\s*(\"(?:[^\"\\]|\\.)*\")\s*;", script)
    marker = "window.WALLPAPERS ="
    start = script.find(marker)
    if not base_match or start == -1:
        raise SystemExit("Omarchy Themes index format changed (missing WALLPAPERS metadata)")
    base_url = json.loads(base_match.group(1))
    payload = script[start + len(marker):].strip()
    if payload.endswith(";"):
        payload = payload[:-1].rstrip()
    try:
        manifest = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Omarchy Themes index format changed: {exc}") from exc
    if not isinstance(manifest, dict):
        raise SystemExit("Omarchy Themes index is not an object")
    return _validated_https_url(base_url, "gallery media base"), manifest


def flatten_aether_catalog(manifest: dict, base_url: str) -> list[dict]:
    """Normalize the website's wallpaper-first manifest into theme variants."""
    base = _validated_https_url(base_url, "gallery media base").rstrip("/") + "/"
    items: list[dict] = []
    for wallpaper_path, raw_meta in manifest.items():
        if not isinstance(wallpaper_path, str) or not isinstance(raw_meta, dict):
            continue
        raw_themes = raw_meta.get("themes")
        if not isinstance(raw_themes, dict):
            continue
        schemes = list(AETHER_VARIANT_ORDER) + sorted(set(raw_themes) - set(AETHER_VARIANT_ORDER))
        for scheme in schemes:
            raw_theme = raw_themes.get(scheme)
            if not isinstance(raw_theme, dict):
                continue
            colors_path = raw_theme.get("colors_toml")
            name = raw_theme.get("name")
            if not isinstance(colors_path, str) or not isinstance(name, str):
                continue
            try:
                validate_theme_name(name)
            except SystemExit:
                continue
            colors_url = urllib.parse.urljoin(base, colors_path.lstrip("/"))
            wallpaper_url = urllib.parse.urljoin(base, wallpaper_path.lstrip("/"))
            preview_path = raw_meta.get("thumb_path") or raw_meta.get("medium_path") or wallpaper_path
            preview_url = urllib.parse.urljoin(base, str(preview_path).lstrip("/"))
            item_id = hashlib.sha256(
                f"{colors_url}\0{wallpaper_url}".encode()
            ).hexdigest()[:20]
            raw_colors = raw_theme.get("colors")
            swatches = {
                key: value
                for key in AETHER_SWATCH_KEYS
                if isinstance(raw_colors, dict)
                and isinstance((value := raw_colors.get(key)), str)
                and HEX_RE.match(value)
            }
            items.append({
                "id": item_id,
                "name": name,
                "title": str(raw_meta.get("title") or Path(wallpaper_path).stem),
                "variant": AETHER_VARIANT_LABELS.get(scheme, scheme.title()),
                "scheme": scheme,
                "tone": str(raw_meta.get("tone") or ""),
                "color": str(raw_meta.get("color") or ""),
                "dimensions": str(raw_meta.get("dimensions") or ""),
                "colors": swatches,
                "colors_url": colors_url,
                "wallpaper_url": wallpaper_url,
                "preview_url": preview_url,
            })
    return items


def load_aether_catalog(refresh: bool = False) -> dict:
    """Fetch the large gallery lazily and cache only its flattened adapter view."""
    cache = _aether_catalog_cache()
    if not refresh and cache.is_file() and time.time() - cache.stat().st_mtime < CATALOG_TTL:
        try:
            return json.loads(cache.read_text())
        except json.JSONDecodeError:
            pass

    try:
        data, _content_type, _final_url = _download_https(AETHER_GALLERY_INDEX, 64 * 1024 * 1024)
        base_url, manifest = _parse_aether_gallery_script(data)
        catalog = {
            "source": AETHER_GALLERY_INDEX,
            "base_url": base_url,
            "items": flatten_aether_catalog(manifest, base_url),
        }
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
        return catalog
    except (Exception, SystemExit):
        # A stale cache is still more useful than dropping the whole source
        # during a temporary network failure.
        if cache.is_file():
            try:
                print("  ! Omarchy Themes refresh failed — using the stale cached catalog")
                return json.loads(cache.read_text())
            except json.JSONDecodeError:
                pass
        raise


def _aether_item(catalog: dict, item_id: str) -> dict | None:
    return next((item for item in catalog.get("items", []) if item.get("id") == item_id), None)


def _user_sources() -> list[str]:
    """Extra repos pinned by the user: ~/.config/themeport/sources.json
    with {"repos": ["owner/repo", ...]}."""
    path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "themeport/sources.json"
    if not path.is_file():
        return []
    try:
        return list(json.loads(path.read_text()).get("repos", []))
    except (json.JSONDecodeError, AttributeError):
        print(f"  ! ignoring malformed {path}")
        return []


def load_catalog(refresh: bool = False) -> dict:
    cache = _catalog_cache()
    if not refresh and cache.is_file() and time.time() - cache.stat().st_mtime < CATALOG_TTL:
        try:
            return json.loads(cache.read_text())
        except json.JSONDecodeError:
            pass

    official = sorted(
        entry["name"]
        for entry in _github_json(
            f"https://api.github.com/repos/{OMARCHY_REPO}/contents/themes?ref={OMARCHY_REF}"
        )
        if entry["type"] == "dir"
    )
    community: list[dict] = []
    try:
        result = _github_json(
            "https://api.github.com/search/repositories?q=omarchy+theme+in:name&sort=stars&per_page=50"
        )
        theme_repo = re.compile(r"^omarchy[-_](.+[-_])?themes?$")
        for item in result.get("items", []):
            name = item["name"].lower()
            # only theme-shaped names (omarchy-<x>-theme); tooling repos like
            # omarchy-theme-hook don't fit. Oddly-named themes can still be
            # installed by owner/repo or pinned in sources.json.
            if theme_repo.match(name) and not item.get("archived"):
                community.append({
                    "repo": item["full_name"],
                    "name": normalize_theme_name(item["name"]),
                    "stars": item["stargazers_count"],
                    "desc": (item.get("description") or "").strip()[:70],
                })
    except Exception as exc:  # noqa: BLE001
        print(f"  ! community search unavailable ({exc}) — official catalog still works")

    catalog = {"official": official, "community": community}
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(catalog))
    return catalog


# keep preview.png — it powers the gallery pickers; skip only lock-screen art
_SKIP_OFFICIAL_FILES = re.compile(r"(^|/)(preview-unlock\.(png|jpe?g)|unlock\.png)$", re.I)


def install_official(name: str, dest_root: Path) -> Path:
    """Install one of basecamp/omarchy's shipped themes (subdirectory of the
    monorepo, so the tarball route doesn't apply)."""
    tree = _github_json(
        f"https://api.github.com/repos/{OMARCHY_REPO}/git/trees/{OMARCHY_REF}?recursive=1"
    )
    prefix = f"themes/{name}/"
    blobs = [e for e in tree["tree"] if e["path"].startswith(prefix) and e["type"] == "blob"]
    if not blobs:
        raise SystemExit(f"official theme '{name}' not found in {OMARCHY_REPO}")

    staging = dest_root / f".staging-{name}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    print(f"fetching official theme '{name}' ...")
    for blob in blobs:
        rel = blob["path"][len(prefix):]
        if _SKIP_OFFICIAL_FILES.search(rel):
            continue
        target = staging / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://raw.githubusercontent.com/{OMARCHY_REPO}/{OMARCHY_REF}/{blob['path']}"
        with urllib.request.urlopen(url, timeout=60) as resp:  # noqa: S310
            target.write_bytes(resp.read())

    load_theme(staging)  # validate before committing to the store

    dest = dest_root / name
    if dest.exists():
        shutil.rmtree(dest)
    shutil.move(str(staging), str(dest))
    (dest / ".themeport-source").write_text(f"{OMARCHY_REPO}#themes/{name}\n")
    return dest


# -------------------------------------------------------------------- pickers


def _swatch(colors: dict[str, str], keys: tuple[str, ...] = ("background", "accent", "red", "yellow", "green", "cyan", "blue", "magenta")) -> str:
    blocks = []
    for key in keys:
        value = colors.get(key, "")
        if HEX_RE.match(value):
            r, g, b = _rgb(value)
            blocks.append(f"\x1b[48;2;{r};{g};{b}m  \x1b[0m")
    return "".join(blocks)


def _installed_themes() -> list[Theme]:
    root = themes_home()
    themes = []
    if root.is_dir():
        for d in sorted(root.iterdir()):
            if d.is_dir() and not d.name.startswith("."):
                try:
                    themes.append(load_theme(d))
                except SystemExit:
                    continue
    return themes


def _self_cmd() -> str:
    import shlex
    return f"{shlex.quote(sys.executable)} {shlex.quote(str(Path(__file__).resolve()))}"


def _fzf(rows: list[str], prompt: str, preview: str | None = None) -> str | None:
    """Run fzf over tab-delimited rows (field 1 = key); return the chosen key."""
    if not shutil.which("fzf"):
        return None
    cmd = ["fzf", "--ansi", "--prompt", prompt, "--delimiter", "\t",
           "--with-nth", "2..", "--height", "100%", "--reverse"]
    if preview:
        cmd += ["--preview", preview, "--preview-window", "right,55%,border-left"]
    try:
        proc = subprocess.run(cmd, input="\n".join(rows), capture_output=True, text=True)
    except Exception:  # noqa: BLE001
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    return proc.stdout.split("\t", 1)[0].strip()


def _hold_open(args: argparse.Namespace) -> None:
    if getattr(args, "hold", False):
        try:
            input("\npress Enter to close...")
        except EOFError:
            pass


def _preview_image_path(theme_dir: Path) -> Path | None:
    for name in ("preview.png", "preview.jpg", "preview.jpeg", "preview2.png"):
        if (theme_dir / name).is_file():
            return theme_dir / name
    if (theme_dir / "backgrounds").is_dir():
        bgs = sorted(
            p for p in (theme_dir / "backgrounds").iterdir()
            if p.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")
        )
        if bgs:
            return bgs[0]
    return None


def _chafa(image: Path) -> bool:
    if not shutil.which("chafa"):
        return False
    cols = os.environ.get("FZF_PREVIEW_COLUMNS", "60")
    lines = os.environ.get("FZF_PREVIEW_LINES", "24")
    # cap image height to leave room for the swatch strip below it
    img_lines = max(int(lines) - 5, 5)
    try:
        subprocess.run(["chafa", "-s", f"{cols}x{img_lines}", str(image)], check=True, timeout=20)
        return True
    except Exception:  # noqa: BLE001
        return False


def _swatch_strip(colors: dict[str, str]) -> str:
    wide = []
    for key in ("background", "accent", "red", "yellow", "green", "cyan", "blue", "magenta"):
        value = colors.get(key, "")
        if HEX_RE.match(value):
            r, g, b = _rgb(value)
            wide.append(f"\x1b[48;2;{r};{g};{b}m    \x1b[0m")
    return "".join(wide)


def _cached_online_preview(key: str) -> Path | None:
    """Lazily fetch a preview image for a not-yet-installed theme."""
    cache_dir = _catalog_cache().parent / "previews"
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", key)
    cached = cache_dir / f"{safe}.png"
    if cached.is_file():
        return cached if cached.stat().st_size > 0 else None
    urls: list[str] = []
    if key.startswith("official:"):
        name = key.split(":", 1)[1]
        urls = [f"https://raw.githubusercontent.com/{OMARCHY_REPO}/{OMARCHY_REF}/themes/{name}/preview.png"]
    elif key.startswith("repo:"):
        repo = key.split(":", 1)[1]
        urls = [
            f"https://raw.githubusercontent.com/{repo}/HEAD/{n}"
            for n in ("preview.png", "preview.jpg", "screenshot.png", "screenshot.jpg")
        ]
    elif key.startswith("aether:"):
        item = _aether_item(load_aether_catalog(), key.split(":", 1)[1])
        if item and item.get("preview_url"):
            urls = [item["preview_url"]]
    for url in urls:
        try:
            data, content_type, _final_url = _download_https(url, 12 * 1024 * 1024)
            _image_extension(data, content_type)
            cached.write_bytes(data)
            return cached
        except (Exception, SystemExit):  # noqa: BLE001
            continue
    cached.write_bytes(b"")  # negative cache: don't retry on every keystroke
    return None


def cmd_preview(args: argparse.Namespace) -> int:
    """Preview pane renderer for the fzf pickers (image + palette swatches)."""
    target = args.target
    if target == "@browse":
        print("browse online sources: official Omarchy, community repos, and Omarchy Themes")
        return 0
    if target == "@aether":
        print(
            "browse Omarchy Themes: 3,000+ wallpapers with Palette, Warm, Cool, "
            "Material and Aether variants\n\nThe large index loads only after you choose this source."
        )
        return 0

    if os.sep in target and Path(target).is_file():  # wallpaper path
        if not _chafa(Path(target)):
            print(Path(target).name)
        return 0

    if target.startswith(("official:", "repo:", "aether:")):
        image = _cached_online_preview(target)
        if image is None:
            print("(no preview image available)")
        elif not _chafa(image):
            print("(image preview needs chafa)")
        if target.startswith("aether:"):
            item = _aether_item(load_aether_catalog(), target.split(":", 1)[1])
            if item:
                print(
                    f"\n{item['title']} — {item['variant']} "
                    f"({item['tone']} {item['color']}, {item['dimensions']})"
                )
                print(_swatch_strip(item.get("colors", {})))
                print(f"{item['name']} — Omarchy Themes / Aether adapter")
            else:
                print("\nOmarchy Themes entry is no longer in the cached catalog")
        else:
            print(f"\n{target.split(':', 1)[1]}  — not installed; Enter installs it")
        return 0

    theme_dir = Path(target) if os.sep in target else themes_home() / target
    try:
        theme = load_theme(theme_dir)
    except SystemExit:
        print(target)
        return 0
    image = _preview_image_path(theme_dir)
    if image:
        _chafa(image)
    print(f"\n{theme.name}  ({theme.mode}, {len(theme.backgrounds)} wallpapers)")
    print(_swatch_strip(theme.colors))
    print(_swatch_strip({k: theme.colors.get(k, "") for k in
                         ("lighter_background", "selection", "muted", "foreground",
                          "bright_foreground", "orange", "brown", "dark_background")}))
    return 0


def _theme_picker_rows(themes: list[Theme]) -> list[str]:
    """Keep online sources visible before the installed-theme rows."""
    rows = [
        "@aether\t[gallery] Omarchy Themes — 3,000+ wallpapers × five variants …",
        "@browse\t[online]  Official Omarchy + community repositories …",
    ]
    rows.extend(
        f"{theme.name}\t{_swatch(theme.colors)}  {theme.name} "
        f"({theme.mode}, {len(theme.backgrounds)} wallpapers)"
        for theme in themes
    )
    return rows


def cmd_pick(args: argparse.Namespace) -> int:
    themes = _installed_themes()
    rows = _theme_picker_rows(themes)
    if args.list:
        for t in themes:
            print(f"{t.name}\t{t.mode}\t{len(t.backgrounds)}")
        return 0
    choice = _fzf(rows, "theme> ", preview=f"{_self_cmd()} preview {{1}}")
    if choice == "@aether":
        return cmd_gallery(argparse.Namespace(
            list=False,
            refresh=False,
            hold=getattr(args, "hold", False),
        ))
    if choice == "@browse":
        return cmd_browse(argparse.Namespace(list=False, refresh=False, hold=getattr(args, "hold", False)))
    if choice is None:
        print("fzf unavailable or nothing chosen — installed themes:")
        for t in themes:
            print(f"  {t.name} ({t.mode})")
        if not themes:
            print("  (none; use `themeport gallery` or `themeport browse`)")
        _hold_open(args)
        return 1
    rc = cmd_set(argparse.Namespace(name=choice, pair=None))
    _hold_open(args)
    return rc


def cmd_browse(args: argparse.Namespace) -> int:
    try:
        catalog = load_catalog(refresh=getattr(args, "refresh", False))
    except Exception as exc:  # noqa: BLE001
        print(f"  ! GitHub catalogs unavailable ({exc}) — Omarchy Themes is still available")
        catalog = {"official": [], "community": []}
    installed = {t.name for t in _installed_themes()}

    rows: list[str] = [
        "@aether\t[gallery]   Omarchy Themes — 3,000+ wallpaper-derived themes …"
    ]
    for name in catalog.get("official", []):
        mark = " [installed]" if name in installed else ""
        rows.append(f"official:{name}\t[official]  {name}{mark}")
    for repo in _user_sources():
        rows.append(f"repo:{repo}\t[pinned]    {repo}")
    for item in catalog.get("community", []):
        mark = " [installed]" if item["name"] in installed else ""
        rows.append(
            f"repo:{item['repo']}\t[community] {item['name']:22} ★{item['stars']:<4} {item['desc']}{mark}"
        )

    if args.list:
        for row in rows:
            print(row.split("\t", 1)[1])
        return 0
    choice = _fzf(rows, "install> ", preview=f"{_self_cmd()} preview {{1}}")
    if choice is None:
        print("nothing chosen")
        _hold_open(args)
        return 1

    if choice == "@aether":
        return cmd_gallery(argparse.Namespace(
            list=False,
            refresh=getattr(args, "refresh", False),
            hold=getattr(args, "hold", False),
        ))

    kind, _, ref = choice.partition(":")
    root = themes_home()
    root.mkdir(parents=True, exist_ok=True)
    try:
        dest = install_official(ref, root) if kind == "official" else install_from_github(ref, root)
    except Exception as exc:  # noqa: BLE001
        print(f"install failed: {exc}")
        _hold_open(args)
        return 1
    theme = load_theme(dest)
    print(f"installed '{theme.name}' ({theme.mode}, {len(theme.backgrounds)} wallpapers)")

    try:
        answer = input(f"apply '{theme.name}' now? [Y/n] ").strip().lower()
    except EOFError:
        answer = "n"
    rc = 0
    if answer in ("", "y", "yes"):
        rc = cmd_set(argparse.Namespace(name=theme.name, pair=None))
    _hold_open(args)
    return rc


def cmd_gallery(args: argparse.Namespace) -> int:
    print("loading Omarchy Themes gallery (the first load downloads its large index) ...")
    try:
        catalog = load_aether_catalog(refresh=getattr(args, "refresh", False))
    except (Exception, SystemExit) as exc:
        print(f"couldn't load the Omarchy Themes gallery ({exc})")
        _hold_open(args)
        return 1

    items = catalog.get("items", [])
    installed = {t.name for t in _installed_themes()}
    rows = []
    for item in items:
        mark = " [installed]" if item["name"] in installed else ""
        details = " ".join(x for x in (item["tone"], item["color"], item["dimensions"]) if x)
        rows.append(
            f"aether:{item['id']}\t[{item['variant']:<8}] {item['title']}  {details}{mark}"
        )

    if args.list:
        for row in rows:
            print(row.split("\t", 1)[1])
        return 0
    choice = _fzf(rows, "gallery> ", preview=f"{_self_cmd()} preview {{1}}")
    if choice is None:
        print("fzf unavailable or nothing chosen")
        _hold_open(args)
        return 1
    item = _aether_item(catalog, choice.split(":", 1)[1])
    if item is None:
        print("the selected gallery entry disappeared; refresh and try again")
        _hold_open(args)
        return 1

    root = themes_home()
    root.mkdir(parents=True, exist_ok=True)
    try:
        dest = install_from_aether_urls(
            item["name"],
            item["colors_url"],
            item["wallpaper_url"],
            root,
            mode=item["tone"] if item["tone"] in ("dark", "light") else None,
            source_label=f"omarchy-themes:{item['name']}",
        )
        theme = load_theme(dest)
    except (Exception, SystemExit) as exc:
        print(f"install failed: {exc}")
        _hold_open(args)
        return 1
    print(f"installed '{theme.name}' ({theme.mode}, {len(theme.backgrounds)} wallpaper) from Omarchy Themes")

    try:
        answer = input(f"apply '{theme.name}' now? [Y/n] ").strip().lower()
    except EOFError:
        answer = "n"
    rc = 0
    if answer in ("", "y", "yes"):
        rc = cmd_set(argparse.Namespace(name=theme.name, pair=None, no_restart=False))
    _hold_open(args)
    return rc


def cmd_handle_url(args: argparse.Namespace) -> int:
    """Desktop protocol entrypoint. It never honors silent browser requests."""
    try:
        spec = parse_aether_apply_url(args.url)
    except (Exception, SystemExit) as exc:
        print(f"ThemePort could not import this Aether link:\n  {exc}")
        _hold_open(args)
        return 2

    print("ThemePort Aether adapter")
    print(f"  theme:     {spec['name']}")
    print(f"  colors:    {spec['colors']}")
    if spec["wallpaper"]:
        print(f"  wallpaper: {spec['wallpaper']}")
    if spec["mode"]:
        print(f"  mode:      {spec['mode']}")
    if spec["requested_silent"]:
        print("  safety:    the link requested silent apply; ThemePort requires confirmation")

    if not args.yes:
        try:
            answer = input(f"\nInstall and apply '{spec['name']}'? [y/N] ").strip().lower()
        except EOFError:
            answer = ""
        if answer not in ("y", "yes"):
            print("cancelled; nothing was downloaded or changed")
            _hold_open(args)
            return 0

    root = themes_home()
    root.mkdir(parents=True, exist_ok=True)
    try:
        dest = install_from_aether_urls(
            spec["name"],
            spec["colors"],
            spec["wallpaper"],
            root,
            mode=spec["mode"],
            source_label=f"aether:{urllib.parse.urlsplit(spec['colors']).hostname}",
        )
        theme = load_theme(dest)
        print(f"installed '{theme.name}' ({theme.mode}, {len(theme.backgrounds)} wallpaper)")
        rc = cmd_set(argparse.Namespace(name=theme.name, pair=None, no_restart=False))
    except (Exception, SystemExit) as exc:
        print(f"import failed: {exc}")
        rc = 1
    _hold_open(args)
    return rc


def _wallpaper_candidates(all_themes: bool) -> list[Path]:
    base = Path.home() / "Pictures/Wallpapers"
    dirs: list[Path] = []
    state_meta = state_root() / "meta.json"
    current = None
    if state_meta.is_file():
        try:
            current = json.loads(state_meta.read_text()).get("name")
        except json.JSONDecodeError:
            current = None
    if not all_themes and current and (base / "themeport" / current).is_dir():
        dirs = [base / "themeport" / current]
    elif (base / "themeport").is_dir():
        dirs = [d for d in sorted((base / "themeport").iterdir()) if d.is_dir()]
    if not dirs and base.is_dir():
        dirs = [base]
    images: list[Path] = []
    for d in dirs:
        images += sorted(
            p for p in d.rglob("*")
            if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")
        )
    return images


def cmd_wallpapers(args: argparse.Namespace) -> int:
    images = _wallpaper_candidates(args.all)
    if not images:
        print("no wallpapers found — `themeport set` copies a theme's backgrounds into ~/Pictures/Wallpapers/themeport/")
        _hold_open(args)
        return 1
    if args.list:
        for p in images:
            print(p)
        return 0
    home = str(Path.home())
    rows = [f"{p}\t{str(p).replace(home, '~')}" for p in images]
    choice = _fzf(rows, "wallpaper> ", preview=f"{_self_cmd()} preview {{1}}")
    if choice is None:
        print("fzf unavailable or nothing chosen")
        _hold_open(args)
        return 1
    if shutil.which("dms") and _run_quiet(["dms", "ipc", "call", "wallpaper", "set", choice]):
        print(f"wallpaper set: {choice}")
    else:
        print(f"couldn't reach DMS — set it manually: {choice}")
    _hold_open(args)
    return 0


def cmd_install(args: argparse.Namespace) -> int:
    root = themes_home()
    root.mkdir(parents=True, exist_ok=True)
    dest = install_from_github(args.source, root)
    theme = load_theme(dest)
    n_bg = len(theme.backgrounds)
    print(f"installed '{theme.name}' ({theme.mode}, {n_bg} wallpapers) -> {dest}")
    print(f"apply with: themeport set {theme.name}")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    root = themes_home()
    rows = []
    if root.is_dir():
        for d in sorted(root.iterdir()):
            if not d.is_dir() or d.name.startswith("."):
                continue
            try:
                theme = load_theme(d)
            except SystemExit:
                continue
            src_file = d / ".themeport-source"
            src = src_file.read_text().strip() if src_file.is_file() else "local"
            rows.append((theme.name, theme.mode, len(theme.backgrounds), src))
    if not rows:
        print(f"no themes installed in {root} — try: themeport install owner/repo")
        return 0
    for name, mode, n_bg, src in rows:
        print(f"{name:24} {mode:5} {n_bg:2} wallpapers  {src}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="themeport", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_render = sub.add_parser("render", help="render a theme dir to an output dir (pure, no system changes)")
    p_render.add_argument("theme_dir")
    p_render.add_argument("-o", "--output", required=True)
    p_render.add_argument("--pair", help="second theme dir of the opposite mode (fills the other DMS slot)")
    p_render.set_defaults(func=cmd_render)

    p_install = sub.add_parser("install", help="download a theme from GitHub into the local theme store")
    p_install.add_argument("source", help="owner/repo, github:owner/repo, or a GitHub URL")
    p_install.set_defaults(func=cmd_install)

    p_list = sub.add_parser("list", help="list installed themes")
    p_list.set_defaults(func=cmd_list)

    p_set = sub.add_parser("set", help="render a theme into the config repo and apply it live")
    p_set.add_argument("name", help="installed theme name (or a path to a theme dir)")
    p_set.add_argument("--pair", help="opposite-mode theme for the other DMS light/dark slot")
    p_set.add_argument("--no-restart", dest="no_restart", action="store_true",
                       help="never restart dms.service (normal switches don't; only "
                            "adopting the themeport slot from another DMS theme does)")
    p_set.set_defaults(func=cmd_set)

    p_browse = sub.add_parser(
        "browse",
        help="pick from the online catalogs (official, community, or Omarchy Themes) and install",
    )
    p_browse.add_argument("--list", action="store_true", help="print the catalog and exit")
    p_browse.add_argument("--refresh", action="store_true", help="bypass the 24h catalog cache")
    p_browse.add_argument("--hold", action="store_true", help="wait for Enter before exiting (for floating terminals)")
    p_browse.set_defaults(func=cmd_browse)

    p_gallery = sub.add_parser(
        "gallery", help="browse the Omarchy Themes wallpaper-derived catalog through the Aether adapter"
    )
    p_gallery.add_argument("--list", action="store_true", help="print the flattened gallery and exit")
    p_gallery.add_argument("--refresh", action="store_true", help="bypass the 24h gallery cache")
    p_gallery.add_argument("--hold", action="store_true", help="wait for Enter before exiting (for floating terminals)")
    p_gallery.set_defaults(func=cmd_gallery)

    p_handle = sub.add_parser("handle-url", help="handle a browser-dispatched aether://apply URL")
    p_handle.add_argument("url")
    p_handle.add_argument(
        "--yes", action="store_true",
        help="confirm explicitly from the command line (desktop/browser dispatch never passes this)",
    )
    p_handle.add_argument("--hold", action="store_true", help="wait for Enter before exiting (for floating terminals)")
    p_handle.set_defaults(func=cmd_handle_url)

    p_preview = sub.add_parser("preview", help="render a picker preview pane (used internally by fzf)")
    p_preview.add_argument("target", help="theme name, official:<name>, repo:<owner/repo>, or an image path")
    p_preview.set_defaults(func=cmd_preview)

    p_pick = sub.add_parser("pick", help="fuzzy-pick an installed theme and apply it (fzf)")
    p_pick.add_argument("--list", action="store_true", help="print installed themes and exit")
    p_pick.add_argument("--hold", action="store_true", help="wait for Enter before exiting (for floating terminals)")
    p_pick.set_defaults(func=cmd_pick)

    p_wp = sub.add_parser("wallpapers", help="fuzzy-pick a wallpaper for the current theme (fzf)")
    p_wp.add_argument("--all", action="store_true", help="browse every downloaded theme's wallpapers")
    p_wp.add_argument("--list", action="store_true", help="print wallpaper paths and exit")
    p_wp.add_argument("--hold", action="store_true", help="wait for Enter before exiting (for floating terminals)")
    p_wp.set_defaults(func=cmd_wallpapers)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
