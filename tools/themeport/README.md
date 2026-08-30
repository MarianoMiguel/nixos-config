# themeport

Install any Omarchy community theme on this Niri + DankMaterialShell NixOS
system, live, without a rebuild.

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
reachable from the bottom of `themeport pick`, so Mod+Ctrl+T covers installed
and not-yet-downloaded themes. Pin extra repos in
`~/.config/themeport/sources.json` (`{"repos": ["owner/repo"]}`) — useful for
themes whose repo name doesn't match the `omarchy-<x>-theme` pattern the search
filter expects. A `GITHUB_TOKEN` or `gh` login raises the GitHub API rate limits
but isn't required.

`themeport pick` shows **Omarchy Themes** and **Official Omarchy + community**
as its first two rows, before installed themes, so both sources are visible
immediately from `Mod+Ctrl+T`.

**Gallery previews:** all picker views render a preview pane on the right —
the theme's `preview.png` (or first wallpaper) drawn in the terminal via
chafa, plus palette swatch strips. Not-yet-installed catalog entries fetch
their preview image lazily into `~/.cache/themeport/previews/`. Wallpaper
rows preview the image itself.

**Keybindings** (`dotfiles/niri/themeport.kdl`, included from config.kdl):
`Mod+Ctrl+T` opens the theme picker, `Mod+Ctrl+W` the wallpaper picker — each
in a floating Ghostty window (`themeport.picker` app-id rule). The binds live
in their own include because DMS regenerates `dms/binds.kdl` and would drop
custom entries. A native DMS/Quickshell plugin picker (like dms-codexbar)
would be a nicer follow-up, but needs to be developed on the Linux box where
QML can actually run; the fzf pickers are the dependable baseline.

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
3. **Apply** — DMS is pointed at the generated theme
   (`~/.config/DankMaterialShell/themes/themeport/theme.json` via settings),
   and DMS's own matugen cascade re-themes Niri, VS Code, Zed, Firefox, GTK
   portals and friends upstream of us. themeport only fills the gaps below.

## Per-app mechanism

| Target | Mechanism | Live reload |
|---|---|---|
| DMS (bar, lock, notifications, launcher) | generated DMS theme JSON + `dms ipc call settings set` | DMS watches the custom theme file and re-runs the matugen cascade; restart only when adopting the themeport slot from another DMS theme |
| Niri (borders, focus ring) | DMS matugen cascade (`niri/dms/colors.kdl`) | niri auto-reload |
| Ghostty | theme file `ghostty/themes/themeport` (Omarchy tpl) | new windows; existing: `ctrl+shift+,` |
| Alacritty | `alacritty/themeport.toml` import (Omarchy tpl) | native live reload |
| tmux | `tmux/themeport.conf`, sourced from tmux.nix | `tmux source-file` on apply |
| btop | theme file + `color_theme` edit in btop.conf | next btop start |
| Neovim | reviewed Themeport template linked as `dankcolors.lua` | built-in fs-watcher hot reload |
| ChatGPT / Codex | generated `codex-desktop.css` injected by the patched Electron main process | refreshes every two seconds and after page loads |
| Chrome | Themeport request validated into a root-owned `BrowserThemeColor` managed policy | live `--refresh-platform-policy` after the policy bridge updates |
| VS Code | theme's marketplace extension, else generated local extension; sets `workbench.colorTheme` | VS Code watches settings.json |
| Wallpapers | copied to `~/Pictures/Wallpapers/themeport/<name>/`, best-effort DMS IPC | on apply |
| Icons | `icons.theme` → gsettings + DMS settings (Yaru/Adwaita sets pre-installed) | on apply |
| File pickers / portals | gsettings `color-scheme` (+ DMS `syncModeWithPortal`) | on apply |
| Obsidian | `dotfiles/themeport/obsidian/themeport.css` (Omarchy tpl) | manual: copy into a vault's `.obsidian/snippets/` |

Not covered: Omarchy shell plugins (QML for their shell, not DMS) and anything
richer than generated color theming in Chromium — Omarchy doesn't do more there
either.

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
- Live-verified on bonhart (2026-08-15): DMS file-watch pickup + matugen
  cascade (no restart — restarting used to kill the 100ms-debounced cascade,
  and on startup the cascade loses a race against DMS's async matugen check),
  `dms ipc call wallpaper set` (only reliable when not restarting), Chrome
  `--refresh-platform-policy` (process detection must match comm `chrome`;
  the NixOS wrapper name never appears in cmdline), VS Code settings edits
  (JSONC — must not go through json.loads) and .vsix fallback install.
