{ pkgs, quickshell, ... }:

let
  # The agent no longer speaks: it types into a Claude Code terminal you can
  # watch, so replies are read rather than heard. Synthesis is gone along with
  # the headless session it used to narrate.
  voiceagent = pkgs.callPackage ../../packages/voiceagent {
    quickshell = quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  # Both the dictation daemon and the live voice agent transcribe through one
  # whisper-server, so a single copy of the model stays resident instead of two.
  whisperPort = 8178;

  # The stock whisper-cpp is a CPU build, which forces a small model to keep
  # transcription under a second. This machine has a Radeon 890M with coopmat
  # matrix cores sitting idle, and Vulkan is the one backend that works across
  # both hosts' GPUs.
  whisperCpp = pkgs.whisper-cpp.override { vulkanSupport = true; };

  # large-v3-turbo on the GPU costs the same wall clock as base.en did on the
  # CPU (~0.9s for a short phrase, measured) while being a far stronger model.
  # Accuracy on real speech was the complaint; this is where it comes from.
  #
  # Fetching the weights into the store keeps the model pinned and the service
  # startable offline. whisper.cpp will happily download a model itself, but it
  # writes into $HOME at first run, which makes the first transcription after a
  # fresh install silently slow and network-dependent.
  whisperModel = pkgs.fetchurl {
    name = "ggml-large-v3-turbo-q5_0.bin";
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin";
    hash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
  };
in
{
  environment.systemPackages = [ voiceagent ];

  systemd.user.services = {
    whisper-server = {
      description = "Local speech-to-text server for voice input";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      # Deliberately no ConditionEnvironment=XDG_CURRENT_DESKTOP=niri here.
      # niri publishes that variable to the systemd user manager slightly after
      # graphical-session.target is reached, so a unit pulled in by the target
      # evaluates the condition too early, fails it, and is skipped without an
      # error anywhere. librepods gets away with the same condition only
      # because it is ordered after dms.service.
      serviceConfig = {
        ExecStart = pkgs.lib.concatStringsSep " " [
          "${whisperCpp}/bin/whisper-server"
          "--host 127.0.0.1"
          "--port ${toString whisperPort}"
          "--model ${whisperModel}"
          "--threads 4"
          "--no-timestamps"
          # whisper-server answers on /inference by default. Serving the
          # OpenAI-shaped path instead means any OpenAI-compatible client can
          # share this one resident model without a translation layer.
          "--inference-path /v1/audio/transcriptions"
        ];
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    voiceagentd = {
      description = "Voice dictation and spoken prompts for Claude Code";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "whisper-server.service" ];
      wants = [ "whisper-server.service" ];
      # No ConditionEnvironment, for the reason spelled out on whisper-server.
      # niri, ghostty, ydotool and quickshell come from the system profile;
      # the voiceagent wrapper adds ~/.local/bin for claude itself.
      path = [
        "/run/current-system/sw"
        "/etc/profiles/per-user/mariano"
      ];
      serviceConfig = {
        # The user manager is started before Niri exports the shell's Qt
        # variables. Force the overlay onto Wayland so Qt does not select the
        # unavailable XCB platform and abort when dictation begins.
        Environment = "QT_QPA_PLATFORM=wayland";
        ExecStart = "${voiceagent}/bin/voiceagent daemon";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
