#!/usr/bin/env python3
"""themeport validation suite: render every fixture theme and check all outputs.

Run: python3 tools/themeport/tests.py
"""

from __future__ import annotations

import json
import re
import sys
import tempfile
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import themeport  # noqa: E402

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "official"
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

EXPECTED_LIGHT = {"catppuccin-latte", "rose-pine", "white", "flexoki-light"}

DMS_REQUIRED_KEYS = {
    "primary", "primaryText", "primaryContainer", "primaryContainerText",
    "secondary", "secondaryText", "secondaryContainer", "secondaryContainerText",
    "tertiary", "tertiaryText", "tertiaryContainer", "tertiaryContainerText",
    "surface", "surfaceText", "surfaceVariant", "surfaceVariantText",
    "surfaceTint", "background", "backgroundText", "outline", "outlineVariant",
    "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest",
    "surfaceContainerLow", "surfaceContainerLowest", "error", "warning", "info",
}

failures: list[str] = []


def check(cond: bool, msg: str) -> None:
    if not cond:
        failures.append(msg)


def validate_render(name: str, outdir: Path, expect_mode: str) -> None:
    prefix = f"[{name}]"

    meta = json.loads((outdir / "meta.json").read_text())
    check(meta["mode"] == expect_mode, f"{prefix} mode {meta['mode']!r} != expected {expect_mode!r}")

    dms = json.loads((outdir / "dms/theme.json").read_text())
    for slot in ("dark", "light"):
        variant = dms[slot]
        missing = DMS_REQUIRED_KEYS - variant.keys()
        check(not missing, f"{prefix} dms {slot} missing keys: {sorted(missing)}")
        for key in DMS_REQUIRED_KEYS:
            value = variant.get(key, "")
            check(bool(HEX_RE.match(value)), f"{prefix} dms {slot}.{key} not hex: {value!r}")

    ala = tomllib.loads((outdir / "alacritty/themeport.toml").read_text())
    check("colors" in ala, f"{prefix} alacritty output has no [colors]")
    for section in ("normal", "bright"):
        check(len(ala["colors"].get(section, {})) == 8, f"{prefix} alacritty colors.{section} != 8 entries")

    ghostty = (outdir / "ghostty/themes/themeport").read_text()
    palette_lines = [ln for ln in ghostty.splitlines() if ln.startswith("palette =")]
    check(len(palette_lines) == 16, f"{prefix} ghostty palette lines = {len(palette_lines)}, want 16")
    check("{{" not in ghostty, f"{prefix} ghostty has unresolved tokens")

    btop = (outdir / "btop/themes/themeport.theme").read_text()
    check('theme[main_bg]' in btop, f"{prefix} btop theme missing main_bg")
    check("{{" not in btop, f"{prefix} btop has unresolved tokens")

    vscode = json.loads((outdir / "vscode/themeport-color-theme.json").read_text())
    check("colors" in vscode and "tokenColors" in vscode, f"{prefix} generated vscode theme incomplete")

    policy = json.loads((outdir / "chrome/color.json").read_text())
    check(bool(HEX_RE.match(policy["BrowserThemeColor"])), f"{prefix} bad BrowserThemeColor")
    check(policy["BrowserColorScheme"] in ("dark", "light"), f"{prefix} bad BrowserColorScheme")

    tmux = (outdir / "tmux/themeport.conf").read_text()
    check("status-style" in tmux and "#" in tmux, f"{prefix} tmux colors incomplete")

    nvim_generated = (outdir / "neovim/generated.lua").read_text()
    check("{{" not in nvim_generated, f"{prefix} generated neovim.lua has unresolved tokens")

    obsidian = (outdir / "obsidian/themeport.css").read_text()
    check("{{" not in obsidian, f"{prefix} obsidian css has unresolved tokens")


def main() -> int:
    themes = sorted(p for p in FIXTURES.iterdir() if p.is_dir())
    if not themes:
        print("no fixtures found", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)

        for theme_dir in themes:
            name = theme_dir.name
            expect_mode = "light" if name in EXPECTED_LIGHT else "dark"
            try:
                theme = themeport.load_theme(theme_dir)
                outdir = tmpdir / name
                for rel, content in themeport.render_all(theme, None).items():
                    dest = outdir / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_text(content)
                validate_render(name, outdir, expect_mode)
            except Exception as exc:  # noqa: BLE001
                failures.append(f"[{name}] render blew up: {exc}")

        # dark+light pairing fills both DMS slots with distinct palettes
        try:
            tn = themeport.load_theme(FIXTURES / "tokyo-night")
            latte = themeport.load_theme(FIXTURES / "catppuccin-latte")
            dms = themeport.build_dms_theme(tn, latte)
            check(dms["dark"]["surface"] == tn.colors["background"], "[pair] dark slot not tokyo-night")
            check(dms["light"]["surface"] == latte.colors["background"], "[pair] light slot not latte")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"[pair] blew up: {exc}")

        # same-mode pairing must be rejected
        try:
            gruv = themeport.load_theme(FIXTURES / "gruvbox")
            themeport.build_dms_theme(tn, gruv)
            failures.append("[pair-same-mode] expected rejection, got success")
        except SystemExit:
            pass

        # legacy theme: palette recovered from alacritty.toml alone
        legacy = HERE / "fixtures" / "legacy-nord"
        try:
            lt = themeport.load_theme(legacy)
            check(lt.mode == "dark", f"[legacy] mode {lt.mode!r} != dark")
            check(lt.colors["background"].lower() == "#2e3440", f"[legacy] bg {lt.colors['background']}")
            check(lt.colors["red"].lower() == "#bf616a", f"[legacy] red {lt.colors['red']}")
            check(HEX_RE.match(lt.colors["accent"]) is not None, "[legacy] accent not derived")
            outdir = tmpdir / "legacy-out"
            for rel, content in themeport.render_all(lt, None).items():
                dest = outdir / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(content)
            validate_render("legacy-nordish", outdir, "dark")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"[legacy] blew up: {exc}")

    if failures:
        print(f"FAIL ({len(failures)}):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"OK — {len(themes)} fixture themes + pairing + legacy all validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
