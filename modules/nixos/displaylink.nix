{ ... }:

{
  # The Elgato Prompter is a DisplayLink device rather than a plain USB-C
  # display, so the kernel cannot drive it on its own. The evdi module exposes
  # it as a virtual DRM output and the proprietary DisplayLinkManager daemon
  # copies frames from that output to the device over USB. niri renders evdi
  # outputs through the primary GPU since 25.11, so nothing is needed on the
  # compositor side.
  #
  # Listing "displaylink" is what activates the upstream NixOS module; the
  # remaining entries restate the default list that this definition would
  # otherwise replace. DisplayLinkManager is socket-free and starts on demand
  # from the udev rule matching the device, so it stays stopped while no
  # DisplayLink hardware is attached.
  services.xserver.videoDrivers = [
    "displaylink"
    "modesetting"
    "fbdev"
  ];
}
