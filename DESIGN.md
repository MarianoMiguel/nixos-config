# NixOS Desktop Experience Design System

## 1. Atmosphere & Identity

A quiet, immediate command center. DMS owns the shell, Niri owns windows, and Alt+Space is the single searchable entry point. The signature is restrained density: useful system state is visible without duplicating controls or turning the bar and lock screen into dashboards.

## 2. Color

Azure Folio is the single visual family. Doré, European Summer and Argentina change only the art. Daylight uses warm near-white `#f7f4e9`; After hours uses navy `#101d33`. Azure, Cobalt and Slate provide three blue inks. DMS extensions consume the generated theme tokens; the greeter consumes the same validated palette.

| Role | DMS token | Usage |
|---|---|---|
| Primary surface | `Theme.surface` | Desktop shell background |
| Nested surface | `Theme.surfaceContainerHigh` | Cards and provider panels |
| Selected surface | `Theme.primarySelected` | Current tab or active state |
| Primary text | `Theme.surfaceText` | Labels and values |
| Secondary text | `Theme.surfaceVariantText` | Metadata and reset times |
| Success | `Theme.success` | Healthy quota state |
| Warning | `Theme.warning` | Quota at 60 percent or more |
| Error | `Theme.error` | Quota at 80 percent or more and errors |

Art uses paper and ink only. Muted semantic colors still distinguish errors, warnings and success. Azure Folio, Themeport and DMS own the shared palette; Qt and KDE applications follow Themeport through its rendered `kdeglobals` and the KDE platform theme.

## 3. Typography

Use Inter for the interface and IBM Plex Mono for terminals and captions. Jacquard 24 is reserved for the large login/lock clock and small host mark. These roles stay fixed across all collections and modes.

| Level | DMS token | Usage |
|---|---|---|
| Large | `Theme.fontSizeLarge` | Provider name |
| Medium | `Theme.fontSizeMedium` | Normal panel content |
| Small | `Theme.fontSizeSmall` | Bar values, quota labels, metadata |

Use medium weight for compact status and bold only for a provider heading. Other extensions inherit these system fonts.

## 4. Spacing & Layout

The login/lock view splits into art on the left and identity, clock and authentication on the right. Its proportions follow the approved live HTML study. The desktop bar uses a thin opaque surface, transparent widgets and restrained outlines; windows have 5-pixel corners and 12-pixel gaps.

Other QML spacing uses `Theme.spacingXS`, `Theme.spacingS`, `Theme.spacingM`, or larger existing DMS tokens. Cards use `Theme.cornerRadius`. Popouts stay within DMS's established 420-pixel compact panel width and must remain readable without horizontal scrolling.

## 5. Components

### System action

- **Structure**: freedesktop desktop item calling the fixed `mariano-system-action` dispatcher.
- **Variants**: open settings, toggle state, launch a reviewed local workflow.
- **States**: searchable, launched, unavailable outside Niri, completed.
- **Accessibility**: plain-language name and comment; keyboard reachable through Alt+Space.
- **Motion**: owned by DMS launcher tokens.

### Status provider switch

- **Structure**: one equal-width theme-native selector per usable provider above one provider card; unavailable providers are excluded instead of shown as misleading zero-percent entries.
- **Variants**: one provider hides the switch; multiple providers show it.
- **States**: default, hover, selected, loading, provider error, no providers.
- **Accessibility**: provider name and binding quota percentage are separate text fields, the percentage never elides, and a check mark plus accessible label identifies selection; color is supplemental.
- **Motion**: selection is immediate; quota meters use the notification timing token.
- **Layout**: a compact flow with at most two columns per row, elided long provider names, pinned percentages, and one readable content card.

### Quota meter

- **Structure**: label, percentage and reset time, track, semantic fill.
- **States**: success, warning, error, unavailable.
- **Accessibility**: every meter has a numeric percentage and label.
- **Motion**: a 60 ms ease-out update; no decorative looping motion.

### Focus pill and panel

- **Structure**: one bar pill replaces the standalone idle-inhibitor pill and opens a single compact panel for Stay Awake, Silence Notifications, Night Light, and local reminders.
- **States**: neutral Focus, active Stay Awake, muted notifications, Night Light, pending reminders, reminder write error.
- **Accessibility**: every toggle has a plain-language label and state description; pending reminders are shown as text and count, not color alone; all controls remain reachable from the bar and the existing Alt+Space actions.
- **Security**: DMS-native session toggles call reviewed singleton APIs directly. Reminder processes use an argv array with the immutable `mariano-reminder` path; reminder text is never evaluated by a shell.
- **Motion**: native DMS switch and popout tokens only, with no plugin-specific looping motion.

### Network speed pill and panel

- **Structure**: a compact bar pill opens one result panel with Download, Upload, Ping, Jitter, server name, and a Run again action.
- **States**: never run, running, result, cancelled, offline or test error.
- **Accessibility**: every metric carries a visible label and unit; running and failure states are textual; the primary action is keyboard reachable.
- **Security and resource use**: tests run only after an explicit click, use HTTPS, have a hard timeout, and disable result sharing by omission. The normalization boundary discards client IP, ISP, server URL, byte counts, and share data before DMS sees the result. Closing the panel cancels an active test. There is no Wi-Fi scan, background polling, result upload, or runtime-downloaded plugin code.
- **Motion**: only the native busy indicator may run longer than 80 ms, because it communicates real in-progress network work; all transitions remain DMS-owned.

### Quattro quality-of-life translation

- Adopt the useful indicator-cluster pattern: persistent state belongs on the bar, while related controls live in one shallow panel.
- Keep the existing DMS owners for Wi-Fi, Bluetooth, audio, power, weather, media, and updates instead of duplicating Quattro panels.
- Do not adopt Quattro's runtime third-party plugin loader, Wi-Fi scanning panel, credential-revealing QR flow, agent launcher, or privileged DNS switching. System plugins remain declarative Nix inputs with reviewed source.

## 6. Motion & Interaction

| Token | Duration | Usage |
|---|---:|---|
| Immediate | 40 ms | DMS base, lock transition, close actions |
| Feedback | 50 ms | Window open, notifications, screenshot UI |
| Meter | 60 ms | Quota and notification state changes |
| Spatial | 70 ms | Workspace and overview movement |
| Maximum | 80 ms | DMS expressive transitions at twice the base |

Motion communicates state and preserves interruptibility. Continuous progress indicators may run longer because they communicate ongoing work rather than delay input. DMS's `AnimationSpeed.None` remains the reduced-motion route.

## 7. Depth & Surface

Use opaque paper surfaces, tonal elevation and a restrained outline. Extensions use `StyledRect` and DMS theme tokens; they do not add custom shadows, gradients, borders, or glass layers.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Every control remains keyboard searchable through Alt+Space.
- State is expressed with text or icon plus color, never color alone.
- Lock-screen notifications remain disabled by default for privacy.
- Authentication stays visible and focused on the minimal lock screen.
- Touch and pointer targets inherit DMS sizing primitives.

### Accepted Debt

| Item | Location | Why accepted | Owner / Exit |
|---|---|---|---|
| Runtime motion and provider-switch visual QA requires an activated Niri session | DMS and Niri shell | Native QML presentation is checked on Bonhart; credential entry is not automated | Verify normal login after activation without interrupting the active session |
