cmux Linux compatibility notes

The pinned 151.0.7922.64 release retries a macOS-only direct terminal renderer
on Linux. `EnsureDirectAttached` calls a frontend that unconditionally rejects
`BeginCmuxTerminalHostInputCutover`; cancellation tears down the working mirror
and schedules another attempt. The resulting recurring surface recreation is
the whole-pane flash, independent of cursor blinking or compositor animations.

`disable-linux-direct-retry.py` applies a one-byte early return to that function
in the pinned x86-64 Debian binary. It verifies the instruction span's SHA-256
and the function's source-location string first, and fails closed on a different
build. `linux-direct-renderer.patch` records the equivalent source change.
This does not disable Chromium's sandbox, GPU acceleration, or normal terminal
resize/recovery. Revisit/remove it when updating cmux; do not carry offsets to a
new release. The existing GLVND lifetime fix is still needed on NixOS.

Source inspected: the official `cmux-browser-source-151.0.7922.64.tar.zst` release
archive, source commit dd7984e7ea68ee42768feebe3691b7b7ffdca6e6. The cmux-tui
protocol source is pinned upstream at f6085bbb9259767f94ed4890b0eb8df609209936.

Other integration changes live beside their owners:

- Themeport updates running cmux backend defaults, then emits OSC 4 colors to
  their user-owned PTYs. The frontend only forwards explicit palette overrides,
  so backend default colors alone cannot update its ANSI palette. No text is
  sent to shell input and running terminal jobs are preserved.
- Ghostty keeps IBM Plex Mono with explicit BlexMono/Symbols Nerd Font fallback.
  Existing cmux processes must restart once to load new font configuration.
- The DMS dock resolves an empty app ID with the exact native cmux title to the
  installed cmux-browser desktop entry. Real application IDs always win; this
  can be removed when upstream sets the custom Wayland widget's app ID.

Validation: the unpatched build repeatedly recreated its terminal while idle;
40 screenshots contained 39 cleared backgrounds and one rendered background.
The patched build produced 40 rendered backgrounds, an identical stable text
region in all frames, and no recurring resize/reconnect events. Live color
updates were confirmed in the native window and its 16-entry palette metadata.
