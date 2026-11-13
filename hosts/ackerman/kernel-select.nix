# Which kernel ackerman boots (m5max-linux docs/j716c-next-daily-plan.md):
#   "avd"   the daily's tree (7.3.0-ackerman-avd, the private input's nixos/kernel);
#   "next"  j716c-next on Aurora's integration/aurora with rolotrealanis98's J716s series
#           (nixos/kernel-next). Its first generation boots the speakers off (the nosound DTB)
#           until the attended speaker check; then the payload takes the sound DTB.
{ lib, ... }:

{
  options.ackerman.kernel = lib.mkOption {
    type = lib.types.enum [
      "avd"
      "next"
    ];
    default = "avd";
    description = "The kernel tree ackerman boots: the daily's (avd) or j716c-next (next).";
  };
}
