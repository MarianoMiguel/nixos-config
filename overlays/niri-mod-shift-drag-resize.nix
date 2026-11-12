# niri hardcodes interactive drag-resize to Mod+right-mouse-drag, which is
# awkward on a trackpad; configurable drag buttons are upstream issue #372.
# Until then, patch Mod+Shift+left-drag to start the same resize, with the
# same edge/corner detection, cursor icons and double-click gestures.
# Mod+Shift+MouseLeft must stay unbound in the niri config: binds consume
# the button press before drag gestures are considered.
final: prev: {
  niri = prev.niri.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/niri-mod-shift-drag-resize.patch ];
  });
}
