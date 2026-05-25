{ ... }:

{
  services.logind.settings.Login = {
    # Some ThinkPad wake paths replay the wake event as a short power-key press
    # after resume. Let lid close drive suspend; ignore software power-key
    # actions so bogus resume events cannot immediately suspend or power off.
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";

    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
    HoldoffTimeoutSec = "30s";
  };
}
