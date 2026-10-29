# Pond session parity

Archived 2026-10-28 with the Pond session; see `../README.md`. Generated from the parity board, which is no longer maintained.

**built** 26 · **missing** 15 · **deviation** 5 · **watching** 4 · **rejected** 2

## Shell

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Sidebar with clock, calendar, media, notifications and quick controls <sub>`sidebar`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `pond-interface shell/Sidebar.qml via modules/nixos/pond.nix` | Preview: clock, minimap, notifications card and bottom controls render; collapse works over IPC. |
| Workspace minimap; drag windows between workspaces <sub>`minimap`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `pond-interface shell/minimap` |  |
| Claude Code / Codex terminal state on the minimap (working, needs input, unread) <sub>`agent-dots`</sub> | built | pond | consume | `pond-interface shell/NiriMsg.qml` | Matches kitty windows only and reads Pond's fish title format. Works when agents run in the Pond session's kitty; Ghostty needs a patch in our fork. |
| Notification toasts, centre and sidebar card <sub>`notifications`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `pond-interface shell/notifications` |  |
| Volume, brightness and keyboard-layout feedback <sub>`osd`</sub> | built | pond | consume | `pond-interface shell/*Feedback.qml, shell/Slider.qml` | External monitors use ddcutil; hardware.i2c is enabled by pond.nix. |
| Update card and restart-recommended badge <sub>`updates`</sub> | missing | pond | port | `pond-interface shell/updates (calls pm -a)` | Needs a pm-compatible shim over mariano-system-update-all. |
| System tray (StatusNotifier) for LibrePods and others <sub>`tray`</sub> | missing | ours | port |  | LibrePods and the Tailscale tray still start with every graphical session but have no tray to show in. |
| Focus: do not disturb, stay awake, reminders <sub>`focus`</sub> | missing | ours | port | `dotfiles/dms-plugins/focus` | Reminder timers keep firing; only the UI is missing. |
| Night Light <sub>`night-light`</sub> | missing | ours | port | `DMS session` |  |
| Claude/Codex quota <sub>`ai-quota`</sub> | missing | ours | port | `dms-codexbar plugin` | Omarchy 4 ships a model-usage widget; ours is CodexBar on DMS. |
| Notifications stacked by sender, snooze, actions on the card <sub>`notification-grouping`</sub> | watching | omarchy | port |  | Omarchy 4.5 RC. |
| World clock <sub>`world-clock`</sub> | missing | ours | port | `dotfiles/dms-plugins/world-clock` | Natural home is Pond's calendar card. |

## Controls

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Wi-Fi and Ethernet panel, including enterprise networks <sub>`wifi`</sub> | built | pond | consume | `pond-interface shell/wifi (nmcli, iw)` |  |
| Bluetooth panel <sub>`bluetooth`</sub> | built | pond | consume | `pond-interface shell/bluetooth` |  |
| Audio output and input panel <sub>`audio`</sub> | built | pond | consume | `pond-interface shell/audio` |  |
| Battery detail and power profiles <sub>`battery`</sub> | built | pond | consume | `pond-interface shell/battery (UPower, power-profiles-daemon)` |  |
| Tailscale and Proton VPN controls <sub>`vpn`</sub> | missing | omarchy | port | `DMS control centre` | Omarchy 4's Tailscale panel (exit-node picker) is the feature reference. |
| Battery charge limit <sub>`battery-limit`</sub> | missing | ours | port | `dotfiles/dms-plugins/battery-limit` | Fits Pond's detailed battery menu. |
| On-demand network speed test <sub>`network-speed`</sub> | missing | ours | port | `dotfiles/dms-plugins/network-speed` | Fits Pond's Wi-Fi speed view. |

## Settings

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Display arrangement, modes, scale, rotation <sub>`display-settings`</sub> | built | pond | consume | `pond-interface shell/settings/display; writes ~/.config/pond/niri/cfg/display.kdl` | Patched at build time to honour POND_NIRI_CONFIG_DIR so the DMS session's ~/.config/niri is never touched. |
| Keyboard layouts and mouse/touchpad settings <sub>`keyboard-settings`</sub> | built | pond | consume | `pond-interface shell/settings/system; writes ~/.config/pond/niri/cfg/input.kdl` |  |
| Display layout in the Pond session <sub>`displays`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `~/.config/pond/niri/cfg/display.kdl (Pond's display settings)` | Pond manages its own layout. Decision 2026-10-27: the laptop panel stays on in Pond, unlike the DMS session, which turns it off when docked. |
| Change the time zone from settings <sub>`timezone-setting`</sub> | deviation | nixos | native | `time.timeZone in hosts/*/common.nix` | Pond runs sudo -n timedatectl, which needs a passwordless sudo rule. NixOS sets the zone declaratively, so the button reports an error instead. |
| Daylight / Unthemed look and wallpaper picker <sub>`appearance`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `pond-interface shell/settings/appearance, Pond.Wallpaper, Pond.Daylight` |  |
| First-run manual and navigation tutorial <sub>`manual`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `pond-interface shell/settings/manual` | The Pond Manual desktop entry is packaged but not on the system path, so it does not appear in the DMS launcher. |

## Session

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Lock screen with the shape-grid password field <sub>`lockscreen`</sub> | built (2026-10-27 nested preview on Bonhart) | pond | consume | `pond-interface lockscreen; PAM service pond-lock` | Preview: user name, Wi-Fi status (Pond.WifiStatus C++ plugin), clock and the shape grid render. Unlocking in a real session is still to check. |
| Fingerprint unlock (Bonhart) <sub>`fingerprint-unlock`</sub> | missing | ours | port | `modules/nixos/fingerprint.nix (DMS session only)` | pond-lock has fprintAuth off because Pond's lock screen only drives a password conversation. Omarchy 4 does fingerprint on its Quickshell lock screen; reference for a port. |
| Idle lock, screens off, hibernate on battery <sub>`idle`</sub> | built | ours | native | `modules/nixos/pond.nix (swayidle + pond-idle)` | Pond has no idle handling. Mirrors the DMS policy: lock at 5 min on battery / 10 min on AC, hibernate after 15 min on battery. |
| Polkit authentication dialogs <sub>`polkit-agent`</sub> | built | ours | native | `modules/nixos/pond.nix (polkit-gnome)` | Functional placeholder that does not look like Pond. Omarchy's Quickshell polkit plugin is the reference for a Pond-styled one. |
| DMS never starts inside the Pond session <sub>`dms-isolation`</sub> | built (2026-10-27 real session on Bonhart (runtime drop-in; permanent after rebuild)) | ours | native | `modules/nixos/pond.nix (ExecCondition on dms.service)` | The first real login showed DMS's bar, dock and wallpaper over Pond: librepods.service starts with every graphical session and wants dms.service. dms.service now skips itself while pond-niri.service runs. |
| Login screen <sub>`greeter`</sub> | missing | pond | consume | `DMS greeter (greetd) for every session today` | Pond's greeter runs under SDDM. Switching display managers affects every session, so it waits for the cut-over. |

## Boot

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Plymouth boot and shutdown animation <sub>`boot-splash`</sub> | missing | pond | consume |  | boot.plymouth can take Pond's theme. Deferred until the session is the default; the LUKS prompt needs checking with it. |
| GRUB menu theme <sub>`grub-theme`</sub> | deviation | nixos | native | `systemd-boot` | We boot with systemd-boot and keep five generations; switching to GRUB only for a theme is not worth it. |

## Launcher

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Pond's Vicinae fork (Mod+Space) <sub>`launcher`</sub> | built (2026-10-27 real session on Bonhart (seen, not yet used)) | pond | consume | `packages/pond-vicinae.nix, pond-vicinae.service` | Built from nixos-unstable's Vicinae 0.29 recipe (input nixpkgs-pond). Shares ~/.config/vicinae with GNOME's Vicinae. Preview: the server starts and shows Vicinae's own first-run onboarding, which Pond's binary also contains. |
| Clipboard history (Mod+V) <sub>`clipboard`</sub> | built | pond | consume | `pond-vicinae` |  |
| Install apps from the launcher <sub>`app-install`</sub> | missing | pond | port |  | Pond's pm and its Vicinae extension are not published. A NixOS version would search nixpkgs/Flatpak and add to the config. |
| Searchable system actions (Super+Space in DMS) <sub>`system-actions`</sub> | missing | ours | port | `modules/nixos/system-actions.nix` | Pond uses Mod+Space for its launcher. Likely becomes a Vicinae extension, like the GNOME one. |

## Tools

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Screenshot and recording keys (Alt+Shift+3/4/5) <sub>`capture`</sub> | built | ours | native | `modules/nixos/pond.nix binds -> mariano-capture` |  |
| Dictation (Alt+A) and voice agent (Alt+S) <sub>`voice`</sub> | built | ours | native | `dotfiles/niri/voice.kdl included by modules/nixos/pond.nix` | The DMS bar indicator for dictation has no Pond equivalent yet. |

## Windows

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Per-workspace tile / float / focus modes <sub>`workspace-modes`</sub> | missing | ours | native | `scripts/niri-modes.py, dotfiles/niri/modes.kdl, DMS plugin` | The daemon and Mod+Alt binds can be included in the Pond session; the bar control needs a Pond-style home. |
| Dock and titlebars on floating workspaces <sub>`float-dock`</sub> | watching | omarchy | port |  | Omarchy 4.5 RC. Its dock talks to Hyprland, so only the idea ports. |

## Apps

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Pond's kitty setup (70% opacity, JetBrains Mono, Pond theme) <sub>`terminal`</sub> | built | pond | consume | `/etc/xdg/kitty/kitty.conf, ~/.config/kitty seeded once` | Pond ships kitty 0.49 with a pond-ripple shader; nixpkgs has 0.45 and the shader is not in the public repo. |
| Pond's fish setup (pure prompt, eza, bat, fzf) <sub>`shell-config`</sub> | watching | pond | consume |  | Your login shell is zsh. The agent dots key off fish's title format, which matters if this is adopted. |

## Look

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Onest, Advent Pro, IBM Plex Mono, JetBrains Mono <sub>`fonts`</sub> | built | pond | consume | `packages/pond-fonts.nix, modules/nixos/pond.nix` |  |
| Pond Gramercy title face <sub>`title-font`</sub> | deviation | pond | consume | `fontconfig alias to the default serif in modules/nixos/pond.nix` | Proprietary and unpublished. Aliased to a serif because its outlined uses in Pond's artwork (the manual title) are serif; an inference, not confirmed. |
| Dark Adwaita for apps <sub>`gtk-theme`</sub> | built | pond | consume | `GTK_THEME in pond-niri.service` | GTK3 only. GTK4/libadwaita follow the color-scheme setting, which the DMS session also writes. |
| Omarchy themes via themeport, Azure Folio <sub>`themes`</sub> | rejected | ours | bridge | `tools/themeport, tools/azure-folio (DMS session)` | Decision 2026-10-27: copy Pond's look directly. Pond hardcodes its colours in Theme.qml, so themes would need a tokenised fork. |

## Input

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Touchpad scroll direction <sub>`scroll-direction`</sub> | deviation | ours | native | `pond-session-prepare drops natural-scroll from the seeded input.kdl` | Matches our GNOME and DMS policy. Pond's settings panel can still turn it on. |

## System

| Capability | Status | Source | Tier | Where | Notes |
|---|---|---|---|---|---|
| Pond's runtime: Qt 6.12 and Quickshell 0.3.2 <sub>`runtime`</sub> | built (2026-10-27 nested preview on Bonhart) | pond | consume | `nixpkgs-pond input; packages/pond-interface.nix ships its own qs` | Pond's QML needs Qt 6.12 (alias targets such as body.contentItem.data fail on 6.11). The Pond session runs its own Quickshell; DMS keeps Qt 6.11 and Quickshell 0.3.1. |
| pond-system-optimizations (sysctl, udev, ananicy, zram) <sub>`system-tuning`</sub> | watching | pond | port | `modules/nixos/hardware-generic.nix has zram` | Not in a public repo. Review rule by rule against power.nix and Bonhart's hardware fixes before adopting any. |
| linux-pond (Clang, ThinLTO, -O3) <sub>`kernel`</sub> | rejected | pond | native | `hosts/bonhart/common.nix (linuxPackages_6_18)` | Same 6.18 LTS series as ours. A custom build would lose the binary cache and risks the EVDI (DisplayLink) module. |
| Rollback (snapper + grub-btrfs on Pond) <sub>`snapshots`</sub> | deviation | nixos | native | `NixOS generations` | Generations cover system rollback; backups.nix covers data. |
