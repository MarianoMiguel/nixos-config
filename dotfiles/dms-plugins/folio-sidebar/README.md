# Folio Sidebar

A native DMS composite plugin owned by this NixOS configuration. No additional
shell fork or DMS source patch is needed for the sidebar.

- **Super+N** or the rightmost bar button toggles the drawer on that display.
- **Super+Ctrl+N** opens Notifications. Escape and outside clicks dismiss it.
- The clock uses Jacquard 24; interface text and captions follow DMS font settings.
- Surfaces follow the shared Folio palette, with 5 px corners, a warm scrim and
  soft shadow. Opening and closing take 90 ms.
- Sections form an accordion. Long content scrolls and drafts remain intact
  while the drawer is closed. Media uses DMS's existing MPRIS controller.
- Sound provides output and microphone volume/mute, plus single-click device
  selection through DMS AudioService. Device aliases and hidden devices follow
  DMS settings. When LibrePods is running, its reported battery status and exported
  noise-control radio actions appear here; no private Bluetooth API is used.
- The footer's sliders button opens the full DMS Control Center.

## Ownership and update boundaries

`SidebarDaemon.qml` owns one Wayland overlay and its IPC handler. All monitor bar
buttons talk to that instance through DMS plugin globals. Opening another DMS
popout dismisses this drawer through `PopoutManager`; locking closes it too.
The overlay reserves no desktop space and retains the native DMS dock and bar.

`PluginContent.qml` adapts the existing `popoutContent` component of Focus,
World Clock, Workspace Modes, Battery Limit and Codex Bar. It instantiates one
controller per visited section, so their logic, settings and refresh behavior
stay with their original plugins. An unavailable plugin produces an explanatory
message rather than breaking the rest of the sidebar. Layout changes target the
drawer display; the Workspace Modes daemon remains the authority.

`NotificationsPanel.qml` and the battery section borrow DMS's native content
components. These, `PopoutManager`, and the widget registry are the small upstream
integration boundary. DMS's composite plugin API is documented, but these QML
content interfaces can change. Keep the flake pinned and run the smoke test after
an update; do not assume any untested DMS version is compatible.

The neutral palette lives in `tools/azure-folio/palettes.py`. Palette builds are
separate from dithering in `build.py`; color iteration does not regenerate art.

## Validation and deployment

Build and activate the normal Bonhart configuration, then restart `dms.service`
to pick up the new immutable plugin generation. Home Manager enables the plugin,
sets the clean bar, and invalidates QML bytecode when plugin sources change.
Use a shell restart after plugin updates: repeated live daemon reloads can leave
stale Quickshell IPC registrations in this pinned version.

Run `python3 scripts/test-folio-sidebar.py` in the repository with DMS running.
It opens every section, checks that the borrowed plugin panels loaded, verifies
the notification adapter, rejects invalid section names, and closes the drawer.
It does not change focus settings, power profiles, workspace modes, or media.
Check light/dark appearance and click-through behavior visually as well.
