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
    cmux = themeport.cmux_theme_colors(outdir / "ghostty/themes/themeport")
    check(len(cmux["palette"]) == 16, f"{prefix} cmux missing ANSI colors")
    check(cmux["bg"] == cmux["palette"]["0"], f"{prefix} cmux background differs from Ghostty")
    check(cmux["fg"] == cmux["palette"]["7"], f"{prefix} cmux foreground differs from Ghostty")

    btop = (outdir / "btop/themes/themeport.theme").read_text()
    check('theme[main_bg]' in btop, f"{prefix} btop theme missing main_bg")
    check("{{" not in btop, f"{prefix} btop has unresolved tokens")

    vscode = json.loads((outdir / "vscode/themeport-color-theme.json").read_text())
    check("colors" in vscode and "tokenColors" in vscode, f"{prefix} generated vscode theme incomplete")

    policy = json.loads((outdir / "chrome/color.json").read_text())
    check(set(policy) == {"BrowserThemeColor"}, f"{prefix} unexpected Chrome policy keys")
    check(bool(HEX_RE.match(policy["BrowserThemeColor"])), f"{prefix} bad BrowserThemeColor")
    # Chrome paints its frame in the seed itself: the terminal's background.
    check(policy["BrowserThemeColor"] == meta["background"], f"{prefix} Chrome frame differs from the background")

    tmux = (outdir / "tmux/themeport.conf").read_text()
    check("status-style" in tmux and "#" in tmux, f"{prefix} tmux colors incomplete")

    vicinae = tomllib.loads((outdir / "vicinae/themeport.toml").read_text())
    check(vicinae["meta"]["variant"] == expect_mode, f"{prefix} vicinae mode mismatch")
    check(vicinae["meta"]["inherits"] == f"vicinae-{expect_mode}", f"{prefix} vicinae base mismatch")
    check(vicinae["colors"]["core"]["background"] == meta["background"], f"{prefix} vicinae background mismatch")
    check(bool(HEX_RE.match(vicinae["colors"]["core"]["accent"])), f"{prefix} vicinae accent invalid")

    nvim_generated = (outdir / "neovim/generated.lua").read_text()
    check("{{" not in nvim_generated, f"{prefix} generated neovim.lua has unresolved tokens")
    check("base16-colorscheme" in nvim_generated, f"{prefix} generated neovim.lua missed palette loader")
    check("_themeport_theme_watcher" in nvim_generated, f"{prefix} generated neovim.lua missed live reload")
    check(meta["background"] in nvim_generated, f"{prefix} generated neovim.lua missed background")

    obsidian = (outdir / "obsidian/themeport.css").read_text()
    check("{{" not in obsidian, f"{prefix} obsidian css has unresolved tokens")

    codex = (outdir / "codex-desktop.css").read_text()
    check("{{" not in codex, f"{prefix} Codex desktop CSS has unresolved tokens")
    check(meta["background"] in codex, f"{prefix} Codex desktop CSS missed the background")

    # GTK: libadwaita variables (not @define-color) and GTK 3 named colors.
    gtk4 = (outdir / "gtk-4.0/gtk.css").read_text()
    check(f"--window-bg-color: {meta['background']};" in gtk4, f"{prefix} gtk4 window color is not the background")
    check(f"--accent-bg-color: {meta['accent']};" in gtk4, f"{prefix} gtk4 accent is not the accent")
    check("@define-color" not in gtk4, f"{prefix} gtk4 uses @define-color, which libadwaita ignores")
    gtk3 = (outdir / "gtk-3.0/gtk.css").read_text()
    check(f"@define-color theme_bg_color {meta['background']};" in gtk3, f"{prefix} gtk3 theme_bg_color is not the background")


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

        # a pair puts light at :root and dark under prefers-color-scheme
        try:
            css = themeport.render_gtk4_css(tn, latte)
            light_part, _, dark_part = css.partition("@media (prefers-color-scheme: dark)")
            check(f"--window-bg-color: {latte.colors['background']};" in light_part, "[gtk-pair] light block is not latte")
            check(f"--window-bg-color: {tn.colors['background']};" in dark_part, "[gtk-pair] dark block is not tokyo-night")
            check(css == themeport.render_gtk4_css(latte, tn), "[gtk-pair] depends on which theme is current")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"[gtk-pair] blew up: {exc}")

        # Obsidian: one theme, light and dark blocks, installed into vaults;
        # only a vault with no theme chosen is switched to it.
        try:
            css = themeport.render_obsidian_theme(tn, latte)
            check(f"--background-primary: {latte.colors['background']};" in css.split(".theme-dark")[0], "[obsidian] light block is not latte")
            check(f"--background-primary: {tn.colors['background']};" in css.split(".theme-dark")[1], "[obsidian] dark block is not tokyo-night")
            import os
            cfg = tmpdir / "obsidian-config"
            state = tmpdir / "obsidian-state"
            for rel, content in themeport.render_all(tn, latte).items():
                (state / rel).parent.mkdir(parents=True, exist_ok=True)
                (state / rel).write_text(content)
            fresh, chosen = tmpdir / "vault-fresh", tmpdir / "vault-chosen"
            for v, appearance in ((fresh, {"cssTheme": "", "enabledCssSnippets": ["dms-colors", "mine"]}),
                                  (chosen, {"cssTheme": "Minimal", "enabledCssSnippets": ["dms-colors"]})):
                (v / ".obsidian").mkdir(parents=True)
                (v / ".obsidian/appearance.json").write_text(json.dumps(appearance))
            (cfg / "obsidian").mkdir(parents=True)
            (cfg / "obsidian/obsidian.json").write_text(json.dumps({"vaults": {"a": {"path": str(fresh)}, "b": {"path": str(chosen)}, "c": {"path": str(tmpdir / "gone")}}}))
            old_env = os.environ.get("XDG_CONFIG_HOME")
            os.environ["XDG_CONFIG_HOME"] = str(cfg)
            try:
                themeport.apply_obsidian(state)
            finally:
                if old_env is None:
                    del os.environ["XDG_CONFIG_HOME"]
                else:
                    os.environ["XDG_CONFIG_HOME"] = old_env
            a = json.loads((fresh / ".obsidian/appearance.json").read_text())
            b = json.loads((chosen / ".obsidian/appearance.json").read_text())
            check((fresh / ".obsidian/themes/Folio/theme.css").read_text() == css, "[obsidian] theme not installed")
            check(a["cssTheme"] == "Folio" and a["enabledCssSnippets"] == ["mine"] and a.get("accentColor") == "", f"[obsidian] fresh vault not switched: {a}")
            check(b == {"cssTheme": "Minimal", "enabledCssSnippets": ["dms-colors"]}, f"[obsidian] chosen vault changed: {b}")
            check((chosen / ".obsidian/themes/Folio/manifest.json").is_file(), "[obsidian] theme not offered in a vault with another theme")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"[obsidian] blew up: {exc}")

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

        # Visible Omarchy wordmarks are excluded from both the gallery and the
        # selected theme default.
        try:
            default_dir = tmpdir / "wallpaper-default"
            default_dir.mkdir()
            (default_dir / "colors.toml").write_text(
                (FIXTURES / "tokyo-night/colors.toml").read_text()
            )
            backgrounds = default_dir / "backgrounds"
            backgrounds.mkdir()
            (backgrounds / "0-gallery-first.jpg").write_bytes(b"gallery")
            (backgrounds / "omarchy.webp").write_bytes(b"default")
            default_theme = themeport.load_theme(default_dir)
            default_meta = json.loads(themeport.render_all(default_theme, None)["meta.json"])
            check(default_theme.backgrounds == ["0-gallery-first.jpg"],
                  "[wallpaper-default] retained an Omarchy wordmark")
            check(default_theme.default_background == "0-gallery-first.jpg",
                  "[wallpaper-default] did not select the first unbranded image")
            check(default_meta["default_background"] == "0-gallery-first.jpg",
                  "[wallpaper-default] metadata lost the unbranded default")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"[wallpaper-default] blew up: {exc}")

        # Aether protocol parsing: URL-decoding, transport flags and the
        # explicit safety boundary around browser-dispatched imports.
        try:
            query = themeport.urllib.parse.urlencode({
                "colors": "https://themes.example/northern/colors.toml",
                "wallpaper": "https://images.example/wall paper.jpg",
                "mode": "light",
                "silent": "true",
                "as_omarchy_theme": "northern-light",
            })
            spec = themeport.parse_aether_apply_url(f"aether://apply?{query}")
            check(spec["name"] == "northern-light", "[aether-url] theme name not parsed")
            check(spec["mode"] == "light", "[aether-url] mode not parsed")
            check(spec["requested_silent"] is True, "[aether-url] silent request not surfaced")
            check("wall%20paper.jpg" in spec["wallpaper"], "[aether-url] wallpaper URL not preserved")
        except BaseException as exc:  # noqa: BLE001
            failures.append(f"[aether-url] valid URL blew up: {exc}")

        invalid_aether_urls = {
            "http": "aether://apply?colors=http%3A%2F%2Fthemes.example%2Fcolors.toml",
            "private": "aether://apply?colors=https%3A%2F%2F127.0.0.1%2Fcolors.toml",
            "edit": "aether://apply?colors=https%3A%2F%2Fthemes.example%2Fcolors.toml&edit=true",
            "blueprint": "aether://apply?external_theme=https%3A%2F%2Fthemes.example%2Ftheme.json",
            "missing-colors": "aether://apply?wallpaper=https%3A%2F%2Fimages.example%2Fwall.jpg",
        }
        for label, url in invalid_aether_urls.items():
            try:
                themeport.parse_aether_apply_url(url)
                failures.append(f"[aether-url-{label}] expected rejection, got success")
            except SystemExit:
                pass

        # Website adapter: flatten the wallpaper-first manifest into selectable
        # theme variants without coupling the rest of ThemePort to its schema.
        try:
            mini_manifest = {
                "dark/blue/wall.jpg": {
                    "title": "Blue Wall",
                    "tone": "dark",
                    "color": "blue",
                    "dimensions": "1920x1080",
                    "thumb_path": "cache/thumb/dark/blue/wall.jpg",
                    "themes": {
                        "palette": {
                            "name": "blue-wall-palette",
                            "colors_toml": "omarchy-themes/blue-wall-palette/colors.toml",
                            "colors": {"background": "#101010", "accent": "#3366ff"},
                        }
                    },
                }
            }
            script = (
                'window.WALLPAPERS_BASE_URL = "https://media.example";\n'
                f"window.WALLPAPERS = {json.dumps(mini_manifest)};\n"
            ).encode()
            base_url, parsed_manifest = themeport._parse_aether_gallery_script(script)
            adapted = themeport.flatten_aether_catalog(parsed_manifest, base_url)
            check(len(adapted) == 1, f"[aether-catalog] got {len(adapted)} rows, want 1")
            check(adapted[0]["variant"] == "Palette", "[aether-catalog] variant label mismatch")
            check(adapted[0]["wallpaper_url"].endswith("/dark/blue/wall.jpg"),
                  "[aether-catalog] wallpaper URL mismatch")
        except BaseException as exc:  # noqa: BLE001
            failures.append(f"[aether-catalog] blew up: {exc}")

        # Download adapter: bounded fetches produce a normal local theme store
        # entry, and URL mode= wins without mutating the downloaded TOML.
        try:
            colors_payload = (FIXTURES / "tokyo-night/colors.toml").read_bytes()
            calls: list[tuple[str, int]] = []

            def fake_download(url: str, limit: int) -> tuple[bytes, str, str]:
                calls.append((url, limit))
                if url.endswith("colors.toml"):
                    return colors_payload, "text/plain", url
                return b"\x89PNG\r\n\x1a\nfixture", "image/png", url

            store = tmpdir / "aether-store"
            store.mkdir()
            imported = themeport.install_from_aether_urls(
                "web-fixture",
                "https://themes.example/web-fixture/colors.toml",
                "https://images.example/wall.jpg",
                store,
                mode="light",
                source_label="omarchy-themes:web-fixture",
                downloader=fake_download,
            )
            web_theme = themeport.load_theme(imported)
            check(web_theme.mode == "light", f"[aether-install] mode {web_theme.mode!r} != light")
            check(web_theme.backgrounds == ["wall.png"],
                  f"[aether-install] backgrounds {web_theme.backgrounds!r}")
            check((imported / "colors.toml").read_bytes() == colors_payload,
                  "[aether-install] downloaded colors were rewritten")
            check(len(calls) == 2 and calls[0][1] < calls[1][1],
                  "[aether-install] fetch size bounds not used")
        except BaseException as exc:  # noqa: BLE001
            failures.append(f"[aether-install] blew up: {exc}")

        # The Niri hotkey's first picker must expose the new source directly,
        # even on a machine with no downloaded themes yet.
        try:
            picker_rows = themeport._theme_picker_rows([])
            check(picker_rows[0].startswith("@aether\t"),
                  "[picker-sources] Omarchy Themes is not the first visible source")
            check(any(row.startswith("@browse\t") for row in picker_rows),
                  "[picker-sources] official/community source missing")
        except BaseException as exc:  # noqa: BLE001
            failures.append(f"[picker-sources] blew up: {exc}")

    if failures:
        print(f"FAIL ({len(failures)}):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"OK — {len(themes)} fixture themes + pairing + legacy + Aether adapter all validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
