{
  lib,
  ghostty,
  makeWrapper,
  python3Packages,
  systemd,
  ydotool,
}:

python3Packages.buildPythonApplication {
  pname = "voiceagent";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3Packages.setuptools ];
  dependencies = with python3Packages; [
    aiohttp
    sounddevice
    webrtcvad

    # webrtcvad 2.0.10 still opens with `import pkg_resources`, which no longer
    # ships with Python. Without setuptools at runtime the daemon dies the
    # first time it tries to listen.
    setuptools
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Import every module: a missing transitive dependency otherwise only shows
  # up as an import error the first time someone speaks.
  pythonImportsCheck = [
    "voiceagent"
    "voiceagent.audio"
    "voiceagent.config"
    "voiceagent.control"
    "voiceagent.overlay"
    "voiceagent.session"
    "voiceagent.stt"
    "voiceagent.theme"
    "voiceagent.terminal"
    "voiceagent.keys"
    "voiceagent.cleanup"
  ];

  checkPhase = ''
    runHook preCheck
    python -m unittest tests -v
    runHook postCheck
  '';

  # claude installs itself into ~/.local/bin, which is not on the path of a
  # systemd user service. The rest are the tools the agent drives: the
  # terminal it types into, busctl to ask GNOME Shell for windows and
  # systemd-run to give the terminal its own scope, and the uinput typist.
  # The optional level panel (overlay = true) finds quickshell on PATH.
  postFixup = ''
    wrapProgram "$out/bin/voiceagent" \
      --prefix PATH : ${
        lib.makeBinPath [
          ghostty
          systemd
          ydotool
        ]
      } \
      --run 'export PATH="$HOME/.local/bin:$PATH"'
  '';

  meta = {
    description = "Local spoken agent for Claude Code, Codex, and the desktop";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "voiceagent";
  };
}
