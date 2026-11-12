# What makes bonhart feel like bonhart, for ackerman (Mariano: "all the comfort stuff I had",
# 2026-11-09), from modules/nixos/desktop.nix, which is GNOME's and not imported here. The input
# feel (repeat, tap, scrolling, speed, no middle-click paste, the keyboard layouts) is niri's, in
# files/niri/ackerman.kdl.
{ ... }:

{
  # Alt+arrows and Alt+U/D as Home, End, Page Up and Page Down, on every keyboard. Super is left
  # alone, as on bonhart.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        alt = {
          d = "pagedown";
          left = "home";
          right = "end";
          u = "pageup";
        };
        "control+alt" = { };
      };
    };
  };

  services.input-remapper.enable = true;
  hardware.opentabletdriver.enable = true;
  hardware.uinput.enable = true;

  # The MX Master 4 over Bluetooth: its high-resolution wheel events made scrolling jump
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Logitech MX Master 4 Bluetooth high-resolution wheel]
    MatchUdevType=mouse
    MatchBus=bluetooth
    MatchVendor=0x046D
    MatchProduct=0xB042
    AttrEventCode=-REL_WHEEL_HI_RES;-REL_HWHEEL_HI_RES
  '';
}
