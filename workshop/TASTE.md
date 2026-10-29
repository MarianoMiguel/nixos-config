# Taste board

Generated from `taste.json` by `scripts/workshop render`. Do not edit by hand.

**like** 11 · **unsure** 50 · **dislike** 2

## Overall

| Thing | Verdict | From | Notes |
|---|---|---|---|
| A calmer, GNOME/macOS-like interface on the DMS session <sub>`gnome-apple-feel`</sub> | like (2026-10-28) | ours | The direction of the revamp: rounded, smooth, translucent, one palette with a good dark mode. |
| Pond as the whole desktop session <sub>`pond-session`</sub> | dislike (2026-10-28) | pond | "Really not ready, and a lot of things I just don't like." Login session removed; pond-preview stays as a live reference. |
| Nothing breaks with real content: long titles, many notifications, empty states <sub>`sturdy-content`</sub> | like (2026-10-28) | ours | "Pay extreme attention to things that could break the design." Every study gets Stress and Empty modes. |
| One design language, Folio; no looks named after their sources <sub>`one-language`</sub> | like (2026-10-28) | ours |  |
| Paper-and-press interface sounds (optional) <sub>`foley`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Color

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Folio's color schemes <sub>`folio-colors`</sub> | like (2026-10-28) | ours | Kept as they are. Looks never change colors. |
| One cohesive palette with a good dark mode across shell, apps and greeter <sub>`dark-mode`</sub> | like (2026-10-28) | ours |  |
| Moonlit plates in dark mode (picture's tones kept) <sub>`moonlit`</sub> | unsure (2026-10-28) | ours | "Dark mode really kills the vibe of the images." The UI's dark mode is liked as is. |
| The bar's ink weight follows the plate's brightness <sub>`adaptive-ink`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Shape

| Thing | Verdict | From | Notes |
|---|---|---|---|
| More rounded corners <sub>`rounded-corners`</sub> | like (2026-10-28) | pond | Panels 16 px, rows and windows 12 px (was 5 px everywhere). First seen in Pond. |
| Concentric corner radii: inner = outer − padding <sub>`concentric-radii`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Continuous (squircle) corners, as a plate mark <sub>`squircles`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Motion

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Smoother, unhurried transitions <sub>`smooth-transitions`</sub> | like (2026-10-28) | pond | Controls 120 ms, panels 220-320 ms, pages 300-520 ms, springs for windows (was 40-90 ms). First seen in Pond. |
| Wallpaper and theme changes choreographed: cover, reveal, the bar fading along <sub>`choreographed-change`</sub> | unsure (2026-10-28) | omarchy | shell/plugins/background/Background.qml (slanted reveal). |
| Panels that grow out of the bar and morph into each other, with press feedback <sub>`morphing-panels`</sub> | unsure (2026-10-28) | omarchy | New in 4.5 rc2. Needs a rewrite: Omarchy uses HyprlandFocusGrab. |
| The plate's dither moving everywhere, in a loop <sub>`moving-dither`</sub> | like (2026-10-28) | ours | Asked for instead of the diagonal light band. |
| Interruptible springs everywhere, matched to niri's <sub>`springs`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Things leave the way they came (exits mirror entries) <sub>`mirror-exits`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Wet-ink shapes that merge (island to sidebar, dock tooltips) <sub>`ink-merge`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Develop on first appearance only; frequent actions stay quick <sub>`first-time-develop`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Material

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Transparency with blur behind shell surfaces <sub>`translucency`</sub> | like (2026-10-28) | macos | Pond's own panels are mostly opaque; this is closer to macOS. |
| Soft layered shadows under panels and windows <sub>`soft-shadows`</sub> | unsure (2026-10-28) | pond | Pond stacks five soft shadows under each panel. |
| Scroll edges dissolve into paper instead of divider lines <sub>`scroll-dissolve`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Hover leaves a faint offset ghost impression <sub>`ghost-impression`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Shell

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Sidebar with clock, calendar, media, notifications and quick controls <sub>`sidebar`</sub> | unsure (2026-10-28) | pond |  |
| Workspace minimap; drag windows between workspaces <sub>`minimap`</sub> | unsure (2026-10-28) | pond |  |
| Claude Code / Codex terminal state on the minimap (working, needs input, unread) <sub>`agent-dots`</sub> | unsure (2026-10-28) | pond |  |
| Notification toasts, centre and sidebar card <sub>`notifications`</sub> | unsure (2026-10-28) | pond |  |
| Volume, brightness and keyboard-layout feedback <sub>`osd`</sub> | unsure (2026-10-28) | pond |  |
| Update card and restart-recommended badge <sub>`updates`</sub> | unsure (2026-10-28) | pond |  |
| Notifications stacked by sender; actions, codes and links on the card; Do Not Disturb; a day of history <sub>`notification-deck`</sub> | unsure (2026-10-28) | omarchy | 4.5 rc1/rc2. Its JS modules are portable; the service asks Hyprland for monitor and fullscreen state. |
| App icons in their own colors and shapes <sub>`real-icons`</sub> | like (2026-10-28) | ours | "Real app icons don't always have that tint." Original by default; plated and printed are options. |
| A dock that never moves for other panels <sub>`dock-stays`</sub> | like (2026-10-28) | ours | "The dock should not move with the sidebar." The sidebar stops above the dock's band instead. |
| Mic, camera and screen-sharing indicators <sub>`privacy-dots`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Floating screenshot thumbnail to drag, mark up or dismiss <sub>`screenshot-thumb`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Undo toasts instead of confirmation dialogs <sub>`undo-toasts`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |
| Builds, downloads and timers as live activities in the island <sub>`live-activities`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Controls

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Wi-Fi and Ethernet panel, including enterprise networks <sub>`wifi`</sub> | unsure (2026-10-28) | pond |  |
| Bluetooth panel <sub>`bluetooth`</sub> | unsure (2026-10-28) | pond |  |
| Audio output and input panel <sub>`audio`</sub> | unsure (2026-10-28) | pond |  |
| Battery detail and power profiles <sub>`battery`</sub> | unsure (2026-10-28) | pond |  |

## Settings

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Pond's settings panels (displays, keyboard, mouse) <sub>`display-settings`</sub> | unsure (2026-10-28) | pond |  |
| Daylight / Unthemed look and wallpaper picker <sub>`appearance`</sub> | unsure (2026-10-28) | pond |  |
| First-run manual and navigation tutorial <sub>`manual`</sub> | unsure (2026-10-28) | pond |  |

## Session

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Lock screen with the shape-grid password field <sub>`lockscreen`</sub> | unsure (2026-10-28) | pond |  |
| Login screen <sub>`greeter`</sub> | unsure (2026-10-28) | pond |  |
| Plymouth boot and shutdown animation <sub>`boot-splash`</sub> | unsure (2026-10-28) | pond |  |
| A screensaver before the lock, with idle timing owned by the shell <sub>`screensaver`</sub> | unsure (2026-10-28) | omarchy | omarchy-screensaver (Rust) animates ASCII art of your branding; dismissing it cancels the lock. Would be built from source. |
| Unlocking with a page turn <sub>`page-turn`</sub> | dislike (2026-10-28) | ours | "The book flipping is weird." Replaced: the page's print lifts, the paper slides aside, the art opens out. |
| The lock clock set in the picture's negative space <sub>`clock-negative-space`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Launcher

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Pond's Vicinae fork (Mod+Space) <sub>`launcher`</sub> | unsure (2026-10-28) | pond |  |
| Clipboard history (Mod+V) <sub>`clipboard`</sub> | unsure (2026-10-28) | pond |  |
| A launcher that acts: app actions, clipboard, Quick Look previews <sub>`launcher-actions`</sub> | unsure (2026-10-28) | research | See digests/2026-10-28-mature-os.md |

## Apps

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Pond's kitty setup (70% opacity, JetBrains Mono, Pond theme) <sub>`terminal`</sub> | unsure (2026-10-28) | pond |  |

## Look

| Thing | Verdict | From | Notes |
|---|---|---|---|
| Onest as the interface font <sub>`fonts`</sub> | unsure (2026-10-28) | pond |  |
| Dark Adwaita for apps <sub>`gtk-theme`</sub> | unsure (2026-10-28) | pond |  |

## Appearance

| Thing | Verdict | From | Notes |
|---|---|---|---|
| One Appearance place: theme, wallpaper, font, bar, windows, dock, animations, lock screen <sub>`appearance-place`</sub> | unsure (2026-10-28) | omarchy | Omarchy 4.5 rc2 made it top-level. Omarchy's is a keyboard menu; ours would be a designed screen. |
| A theme as a bundle: palette, wallpapers, preview, lock art, light and dark; last wallpaper remembered per theme <sub>`theme-bundles`</sub> | unsure (2026-10-28) | omarchy | Maps onto Azure Folio's collections (Doré, European Summer, Argentina). |
| Visual picker for wallpapers and themes <sub>`wallpaper-picker`</sub> | unsure (2026-10-28) | omarchy | Omarchy: carousel of skewed cards (shell/plugins/image-picker), no Hyprland imports. |
| A theme change as one event: visible apps recolor first, the rest after, one notification if anything fails <sub>`theme-switch`</sub> | unsure (2026-10-28) | omarchy | bin/omarchy-theme-set builds, swaps atomically and ignores outdated recolors. Ours would drive themeport. |
| Video wallpapers, with a still frame on the lock screen <sub>`video-wallpapers`</sub> | unsure (2026-10-28) | omarchy | Omarchy's player (OWE) is Hyprland-only; would need another player that works on niri. |

## Foundations

| Thing | Verdict | From | Notes |
|---|---|---|---|
| One token file with a section per surface, so every screen draws from the same named colors and shapes <sub>`surface-tokens`</sub> | unsure (2026-10-28) | omarchy | Omarchy: shell.toml feeding Color and Style singletons. Ours would be emitted by themeport. |
| One keyboard menu for every action, defined as data <sub>`menu-as-data`</sub> | unsure (2026-10-28) | omarchy | default/omarchy/omarchy-menu.jsonc; the same menu doubles as dmenu. Omarchy has no settings screens: Setup > Monitors opens a config file. |
