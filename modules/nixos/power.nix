{ ... }:

{
  services.logind.settings.Login = {
    # Some ThinkPad wake paths replay the wake event as a short power-key press
    # after resume, which logind can interpret as a request to suspend again.
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";

    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
    HoldoffTimeoutSec = "30s";
  };
}
