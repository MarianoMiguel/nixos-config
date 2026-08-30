"""Configuration, defaults first and ~/.config/voiceagent/config.toml over it."""

from __future__ import annotations

import logging
import os
import tomllib
from dataclasses import dataclass, fields
from pathlib import Path

log = logging.getLogger("voiceagent.config")


@dataclass
class Config:
    # Shared with voxtype: one whisper-server holds the model for both.
    whisper_endpoint: str = "http://127.0.0.1:8178"
    whisper_timeout: float = 60.0

    # The visible half: a real Claude Code terminal, and the floating panel.
    terminal_command: list[str] | None = None
    quickshell: str = "quickshell"
    overlay_qml: str = ""

    # Tidy the transcript before typing it. Costs about a second; set to false
    # for the raw transcript.
    cleanup: bool = True
    cleanup_model: str = "claude-haiku-4-5-20251001"
    cleanup_timeout: float = 8.0

    input_device: str | int | None = None
    output_device: str | int | None = None

    # webrtcvad 0-3. 3 rather than the usual 2: the internal microphone here
    # reads close to full scale, and at 2 it opens an utterance on room noise,
    # which both types junk and holds the idle timeout open forever. Lower it
    # if quiet speech gets clipped.
    vad_aggressiveness: int = 3
    # Trailing silence that ends an utterance. Shorter feels snappier but cuts
    # people off mid-thought.
    utterance_end_ms: int = 600

    # How long dictation keeps listening once you stop talking. Comfortably
    # longer than the utterance endpoint above, so pausing to think does not
    # close the microphone, but short enough that you do not have to remember
    # to press Alt+A a second time. Agent mode does not use this: it closes as
    # soon as the one prompt is sent.
    dictation_idle_secs: float = 4.5

    # Without echo cancellation the microphone hears the speakers, so the
    # assistant would transcribe itself. Turning this off enables true barge-in
    # on a headset.
    mute_while_speaking: bool = True

    # How long a spoken "should I?" waits before giving up and denying.
    approval_timeout: float = 60.0

    model: str | None = None
    cwd: Path = Path.home()

    def overlay_qml_path(self) -> Path:
        """The panel ships beside this module, so the default needs no wiring."""
        if self.overlay_qml:
            return Path(self.overlay_qml)
        return Path(__file__).with_name("overlay.qml")


def config_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(base) / "voiceagent" / "config.toml"


def load(path: Path | None = None) -> Config:
    config = Config()
    path = path or config_path()

    try:
        parsed = tomllib.loads(path.read_bytes().decode("utf-8"))
    except FileNotFoundError:
        parsed = {}
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        log.error("ignoring %s (%s)", path, exc)
        parsed = {}

    known = {field.name: field for field in fields(Config)}
    for key, value in parsed.items():
        field = known.get(key)
        if field is None:
            log.warning("unknown setting %r in %s", key, path)
            continue
        setattr(config, key, Path(value).expanduser() if field.type == "Path" else value)

    # The Nix module points these at the store; the environment is how they get
    # here without baking store paths into a user-editable config file.
    if env := os.environ.get("VOICEAGENT_PIPER"):
        config.piper = env
    if env := os.environ.get("VOICEAGENT_VOICE"):
        config.voice = Path(env)
    if env := os.environ.get("VOICEAGENT_WHISPER_ENDPOINT"):
        config.whisper_endpoint = env
    if env := os.environ.get("VOICEAGENT_QUICKSHELL"):
        config.quickshell = env
    if env := os.environ.get("VOICEAGENT_OVERLAY_QML"):
        config.overlay_qml = env

    return config
