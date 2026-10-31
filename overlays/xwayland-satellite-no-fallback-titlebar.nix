# niri hides the xdg-decoration global unless prefer-no-csd is set, and it is
# not set here: apps draw their own title bars with Interstellar's window
# lights. xwayland-satellite then draws a fallback bar of its own on every
# X11 window that wants a frame, a fixed white strip with a title and a close
# box that no theme reaches. Patch it out: X11 windows go without a title
# bar, as they did under prefer-no-csd.
final: prev: {
  xwayland-satellite = prev.xwayland-satellite.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/xwayland-satellite-no-fallback-titlebar.patch ];
  });
}
