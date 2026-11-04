# themeport

Apply a palette to every app on this GNOME NixOS system, live, without a
rebuild. The system's `themeport` wrapper (modules/nixos/themeport.nix) is a
closed catalog: Interstellar's looks (`themeport look`) and the themes shipped
in the Nix store; online installs and galleries below are disabled there.

```
themeport install sc0ttman/omarchy-one-dark-pro-theme
themeport set one-dark-pro
themeport set tokyo-night --pair catppuccin-latte   # dark + light slots
themeport list
themeport pick          # fzf theme picker with color swatches
themeport wallpapers    # fzf wallpaper picker for the current theme (--all for every theme)
themeport browse        # official/community catalog + the Omarchy Themes gallery source
themeport gallery       # direct: 3,000+ wallpapers × five Aether-generated variants
```

`browse` lists every theme shipped with Omarchy (fetched live from
basecamp/omarchy, cached 24h — `--refresh` to bust) plus GitHub community
themes sorted by stars, marks what's already installed, and installs + applies
your selection. Its **Omarchy Themes** row opens bjarneo's wallpaper-first
gallery as an additional source: each wallpaper becomes five selectable
Palette/Warm/Cool/Material/Aether themes. The gallery's large index is fetched
only after that source is chosen and cached for 24 hours. Everything is also
reachable from the bottom of `themeport pick`, so one picker covers installed
and not-yet-downloaded themes. Pin extra repos in
`~/.config/themeport/sources.json` (`{"repos": ["owner/repo"]}`) — useful for
themes whose repo name doesn't match the `omarchy-<x>-theme` pattern the search
filter expects. A `GITHUB_TOKEN` or `gh` login raises the GitHub API rate limits
but isn't required.

`themeport pick` shows **Omarchy Themes** and **Official Omarchy + community**
as its first two rows, before installed themes, so both sources are visible
immediately.

**Gallery previews:** all picker views render a preview pane on the right —
the theme's `preview.png` (or first wallpaper) drawn in the terminal via
chafa, plus palette swatch strips. Not-yet-installed catalog entries fetch
their preview image lazily into `~/.cache/themeport/previews/`. Wallpaper
rows preview the image itself.

**No global shortcut** under GNOME: run `themeport pick` or `themeport
wallpapers` in a terminal. (The niri session bound them to Mod+Ctrl+T and
Mod+Ctrl+W; a Vicinae command would be the natural successor.)

## Aether protocol adapter

The NixOS module registers `themeport-aether-handler.desktop` for
`x-scheme-handler/aether`. This makes the **Apply** buttons on
`https://bjarneo.github.io/omarchy-themes/` useful without installing Aether:
the handler translates the link's remote `colors.toml`, wallpaper, mode and
theme name into a normal ThemePort theme, then uses the existing render/apply
pipeline.

Browser links always open a floating confirmation terminal that shows both
download sources. ThemePort intentionally ignores `silent=true`: Aether's own
protocol documentation notes that any webpage can construct a silent-apply
link. Imports accept only bounded public HTTPS downloads and JPEG/PNG/WebP
wallpapers. Aether blueprint JSON, wallpaper-only links and the Aether editor
action are outside this adapter; the gallery's **Apply** action is supported.

The same parser can be inspected manually without changing anything by
answering no at the prompt:

```
themeport handle-url 'aether://apply?colors=https%3A%2F%2Fexample.com%2Fcolors.toml'
```

## How it works

1. **Parse** — a theme's `colors.toml` (Omarchy ≥ 4) or, for legacy themes,
   its `alacritty.toml`, is resolved into the same color table Omarchy's own
   `omarchy-theme-color --all` produces. The alias/derivation cascade is a
   line-for-line port, so any theme Omarchy accepts, we accept.
2. **Render** — the palette runs through Omarchy's vendored templates
   (`templates/omarchy/*.tpl`, pinned rev in `UPSTREAM_REV`) plus our own
   targets. Outputs land in
   `~/.local/state/nixos-config/dotfiles/themeport/`, independent of where the
   NixOS repository was cloned. Home Manager seeds this state from the checked-in
   defaults the first time a host is activated and preserves later live changes.
3. **Apply** — GNOME's color scheme and icon theme are set through
   gsettings, the wallpaper through `mariano-set-wallpaper`, and every app
   below reads its rendered file (live where the app allows it).

## Per-app mechanism

| Target | Mechanism | Live reload |
|---|---|---|
| Login screen (DMS's greeter, modules/nixos/login-screen.nix) | `dms/theme.json`, linked as `~/.config/DankMaterialShell/themes/themeport/theme.json`, the greeter's custom theme (Interstellar's look binds its main roles) | copied when greetd next starts |
| Ghostty | theme file `ghostty/themes/themeport` (Omarchy tpl) | new windows; existing: `ctrl+shift+,` |
| Alacritty | `alacritty/themeport.toml` import (Omarchy tpl) | native live reload |
| tmux | `tmux/themeport.conf`, sourced from tmux.nix | `tmux source-file` on apply |
| btop | theme file + `color_theme` edit in btop.conf | next btop start |
| Neovim | reviewed Themeport template linked as `lua/plugins/themeport.lua` | built-in fs-watcher hot reload |
| ChatGPT / Codex | generated `codex-desktop.css` injected by the patched Electron main process | refreshes every two seconds and after page loads |
| Chrome | Themeport request validated into a root-owned `BrowserThemeColor` managed policy | live `--refresh-platform-policy` after the policy bridge updates |
| VS Code | renders `vscode/themeport-color-theme.json`; the system wrapper does not install it (theme metadata never installs extensions) | — |
| Wallpapers | copied to `~/Pictures/Wallpapers/themeport/<name>/`, set with `mariano-set-wallpaper` (`org.gnome.desktop.background` `picture-uri` and `picture-uri-dark`) | on apply |
| Icons | `icons.theme` → gsettings (Yaru/Adwaita sets pre-installed) | on apply |
| GTK 4 / libadwaita (Files, the GNOME file chooser behind the portal) | `gtk-4.0/gtk.css`: libadwaita's CSS variables, light at `:root`, dark under `prefers-color-scheme` | mode switches live; a new palette reaches newly started apps |
| GTK 3 | `gtk-3.0/gtk.css`: `theme_*` and adw-gtk3 named colors for the current mode | next app start |
| File pickers / portals | gsettings `color-scheme` | on apply |
| Obsidian | a theme named Folio (light and dark in one file) copied into every vault in `~/.config/obsidian/obsidian.json`; a vault with no theme chosen is switched to it (and a `dms-colors` snippet left from the DMS desktop turned off) | mode switches live with "Adapt to system"; a new palette when Obsidian reloads the theme |

Not covered: GNOME Shell itself (top bar, overview, notifications keep
Adwaita's look), Omarchy shell plugins (QML for their shell) and anything
richer than generated color theming in Chromium — Omarchy doesn't do more
there either.

## Nix wiring (one-time, already in this repo)

- `modules/nixos/themeport.nix` — packages the CLI and Aether protocol handler,
  declares its MIME association, ships Yaru/Adwaita icon sets, and symlinks the
  browser policy from `/etc` into the writable tier.
- `modules/nixos/home.nix` — out-of-store symlinks for every rendered file;
  VS Code `settings.json` moved to the writable tier.
- `dotfiles/ghostty/config.ghostty` → `theme = themeport`;
  `dotfiles/alacritty/alacritty.toml` → colors moved to the import;
  `modules/nixos/tmux.nix` → sources the themeport conf.
- `dotfiles/themeport/` is seeded from `seed/rose-pine-bonhart` (the palette
  this machine already ran), so the first rebuild changes nothing visually.

## Upstream flow

`./update-templates.sh` re-vendors Omarchy's templates from the quattro
branch and records the rev — that is how upstream theming improvements arrive
here. Then run `python3 tests.py` (validates the official fixture themes, a
dark+light pairing, a legacy alacritty-only theme, and the Aether URL/catalog/
download adapters) and rebuild.

## Verification status

- Rendering, install, list, set: tested end-to-end (sandboxed) on macOS.
- Live-verified on bonhart (2026-08-15): Chrome `--refresh-platform-policy`
  (process detection must match comm `chrome`; the NixOS wrapper name never
  appears in cmdline), VS Code settings edits (JSONC — must not go through
  json.loads) and .vsix fallback install.
- GNOME wallpaper through gsettings: not yet verified on the live session.
