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
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tomllib
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATES_DIR = HERE / "templates" / "omarchy"

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

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
    return json.dumps(
        {"BrowserThemeColor": colors["background"], "BrowserColorScheme": colors["mode"]},
        indent=2,
    ) + "\n"


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


def repo_root() -> Path:
    if env := os.environ.get("THEMEPORT_REPO"):
        return Path(env)
    return Path.home() / "Development/personal/nixos-config"


def _run_quiet(cmd: list[str]) -> bool:
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=30)
        return True
    except Exception:  # noqa: BLE001
        return False


def _is_running(name: str) -> bool:
    return _run_quiet(["pgrep", "-x", name]) or _run_quiet(["pgrep", "-f", name])


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


def apply_dms(state: Path, meta: dict, repo: Path) -> None:
    settings = repo / "dotfiles/dms/settings.json"
    theme_path = Path.home() / ".config/DankMaterialShell/themes/themeport/theme.json"
    updates = {
        "currentThemeCategory": "custom",
        "currentThemeName": "custom",
        "customThemeFile": str(theme_path),
    }
    if meta.get("icons"):
        updates["iconThemeDark"] = meta["icons"]
        updates["iconThemeLight"] = meta["icons"]
    if _edit_json(settings, updates):
        print(f"  dms: settings updated -> {meta['name']}")
    # DMS watches its settings/theme files; if the running shell doesn't pick
    # it up, a shell restart is the reliable fallback.
    print("  dms: if the shell doesn't react, run: systemctl --user restart dms.service")


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
    dest = Path.home() / "Pictures/Wallpapers/themeport" / theme.name
    dest.mkdir(parents=True, exist_ok=True)
    for bg in theme.backgrounds:
        shutil.copy2(theme.src / "backgrounds" / bg, dest / bg)
    first = dest / theme.backgrounds[0]
    if shutil.which("dms") and _run_quiet(["dms", "ipc", "call", "wallpaper", "set", str(first)]):
        print(f"  wallpaper: {first.name} ({len(theme.backgrounds)} copied)")
    else:
        print(f"  wallpaper: {len(theme.backgrounds)} copied to {dest} (set one via the DMS settings UI)")


def apply_vscode(state: Path, meta: dict, repo: Path) -> None:
    settings = repo / "dotfiles/vscode/User/settings.json"
    vscode = meta.get("vscode") or {}
    ext, label = vscode.get("extension"), vscode.get("name")
    editor = shutil.which("code") or shutil.which("codium")

    if ext and editor:
        if _run_quiet([editor, "--install-extension", ext]):
            print(f"  vscode: installed {ext}")
        else:
            print(f"  ! vscode: could not install {ext} — theme may not apply until you install it")
    if not (ext and label):
        # no upstream descriptor: register the generated theme as a local extension
        ext_dir = Path.home() / ".vscode/extensions/themeport.themeport-theme-1.0.0"
        (ext_dir / "themes").mkdir(parents=True, exist_ok=True)
        shutil.copy2(state / "vscode/themeport-color-theme.json", ext_dir / "themes/themeport-color-theme.json")
        (ext_dir / "package.json").write_text(json.dumps({
            "name": "themeport-theme",
            "displayName": "Themeport",
            "publisher": "themeport",
            "version": "1.0.0",
            "engines": {"vscode": "^1.60.0"},
            "contributes": {"themes": [{
                "label": "Themeport",
                "uiTheme": "vs-dark" if meta["mode"] == "dark" else "vs",
                "path": "./themes/themeport-color-theme.json",
            }]},
        }, indent=2) + "\n")
        label = "Themeport"
        print("  vscode: generated local theme extension")
    if _edit_json(settings, {"workbench.colorTheme": label}):
        print(f"  vscode: colorTheme -> {label}")


def apply_browsers(meta: dict) -> None:
    for exe in ("google-chrome-stable", "brave"):
        if shutil.which(exe) and _is_running(exe):
            if _run_quiet([exe, "--refresh-platform-policy", "--no-startup-window"]):
                print(f"  {exe}: policy refreshed live")
        # not running: the policy file applies on next launch


def apply_terminals(repo: Path) -> None:
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

    repo = repo_root()
    state = repo / "dotfiles/themeport"
    if not (repo / "flake.nix").is_file():
        raise SystemExit(f"{repo} doesn't look like the nixos-config repo (set THEMEPORT_REPO)")

    files = render_all(theme, other)
    for rel, content in files.items():
        dest = state / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
    meta = json.loads(files["meta.json"])
    print(f"applying '{theme.name}' ({theme.mode}){f' + {other.name}' if other else ''}:")

    apply_dms(state, meta, repo)
    apply_mode(meta)
    apply_icons(meta)
    apply_wallpapers(theme, meta)
    apply_vscode(state, meta, repo)
    apply_browsers(meta)
    apply_terminals(repo)
    apply_btop()
    print("done. rendered state lives in dotfiles/themeport/ — review with: git diff")
    return 0


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


def _fzf(rows: list[str], prompt: str) -> str | None:
    """Run fzf over tab-delimited rows (field 1 = key); return the chosen key."""
    if not shutil.which("fzf"):
        return None
    try:
        proc = subprocess.run(
            ["fzf", "--ansi", "--prompt", prompt, "--delimiter", "\t",
             "--with-nth", "2..", "--height", "100%", "--reverse"],
            input="\n".join(rows), capture_output=True, text=True,
        )
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


def cmd_pick(args: argparse.Namespace) -> int:
    themes = _installed_themes()
    if not themes:
        print("no themes installed — try: themeport install owner/repo")
        _hold_open(args)
        return 1
    rows = [
        f"{t.name}\t{_swatch(t.colors)}  {t.name} ({t.mode}, {len(t.backgrounds)} wallpapers)"
        for t in themes
    ]
    if args.list:
        for t in themes:
            print(f"{t.name}\t{t.mode}\t{len(t.backgrounds)}")
        return 0
    choice = _fzf(rows, "theme> ")
    if choice is None:
        print("fzf unavailable or nothing chosen — themes:")
        for t in themes:
            print(f"  {t.name} ({t.mode})")
        _hold_open(args)
        return 1
    rc = cmd_set(argparse.Namespace(name=choice, pair=None))
    _hold_open(args)
    return rc


def _wallpaper_candidates(all_themes: bool) -> list[Path]:
    base = Path.home() / "Pictures/Wallpapers"
    dirs: list[Path] = []
    state_meta = repo_root() / "dotfiles/themeport/meta.json"
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
    choice = _fzf(rows, "wallpaper> ")
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
    p_set.set_defaults(func=cmd_set)

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
