"""Microphone capture with voice-activity endpointing, and playback.

The capture loop runs for the whole session rather than only while the agent is
listening, because barge-in needs to hear the user start talking *over* the
reply. Utterances are emitted on a queue; what to do with one is the session's
decision, not this module's.
"""

from __future__ import annotations

import array
import asyncio
import collections
import logging
import queue
import threading
import time

import sounddevice as sd
import webrtcvad


def audioop_max(frame: bytes) -> int:
    """Peak absolute sample. Python 3.13 dropped the audioop module."""
    samples = array.array("h")
    samples.frombytes(frame)
    return max((abs(sample) for sample in samples), default=0)

log = logging.getLogger("voiceagent.audio")

RATE = 16000
FRAME_MS = 20
FRAME_BYTES = RATE * FRAME_MS // 1000 * 2  # 16-bit mono


class Utterance:
    __slots__ = ("pcm", "seconds")

    def __init__(self, pcm: bytes):
        self.pcm = pcm
        self.seconds = len(pcm) / 2 / RATE


class Recorder:
    """Emits an Utterance each time the user finishes speaking.

    Also raises `speech_started` the moment speech begins, which is what lets
    the session cut off playback before the transcript exists.
    """

    def __init__(
        self,
        loop: asyncio.AbstractEventLoop,
        device: str | int | None = None,
        aggressiveness: int = 2,
        start_frames: int = 5,
        end_ms: int = 600,
        min_ms: int = 300,
        max_ms: int = 30000,
    ):
        self.loop = loop
        self.device = device
        self.vad = webrtcvad.Vad(aggressiveness)
        self.start_frames = start_frames
        self.end_frames = end_ms // FRAME_MS
        self.min_frames = min_ms // FRAME_MS
        self.max_frames = max_ms // FRAME_MS

        self.utterances: asyncio.Queue[Utterance] = asyncio.Queue()
        self.speech_started = asyncio.Event()
        # Smoothed 0..1 input level, read by the overlay's blurb. Kept here
        # rather than recomputed downstream because this is the only place the
        # raw frames exist.
        self.level = 0.0
        # When speech was last heard, for the dictation idle timeout. Measured
        # on voiced frames rather than on completed utterances, so a long
        # sentence with pauses in it does not look like silence.
        self.last_voice_at = time.monotonic()

        self._stream: sd.RawInputStream | None = None
        self._frames: queue.Queue[bytes | None] = queue.Queue()
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        # Ignore our own speaker output. Set while the assistant is talking on
        # a device without echo cancellation.
        self.muted = False

    def start(self) -> None:
        if self._stream is not None:
            return
        self._stop.clear()
        self._stream = sd.RawInputStream(
            samplerate=RATE,
            blocksize=RATE * FRAME_MS // 1000,
            device=self.device,
            channels=1,
            dtype="int16",
            callback=self._on_audio,
        )
        self._stream.start()
        self.last_voice_at = time.monotonic()
        self._thread = threading.Thread(target=self._consume, name="vad", daemon=True)
        self._thread.start()
        log.info("microphone open (%s)", self.device or "default")

    def stop(self) -> None:
        if self._stream is None:
            return
        self._stop.set()
        self._frames.put(None)
        self._stream.stop()
        self._stream.close()
        self._stream = None
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None
        log.info("microphone closed")

    def _on_audio(self, indata, frames, time_info, status) -> None:  # sounddevice thread
        if status:
            log.debug("audio status: %s", status)
        self._frames.put(bytes(indata))

    def _consume(self) -> None:
        """Endpointing.

        webrtcvad is per-frame and jittery, so speech starts only after several
        voiced frames in a row and ends only after a longer unvoiced run. The
        pre-roll buffer keeps the syllables that arrive before the detector has
        made up its mind -- without it every utterance loses its first word.
        """
        preroll: collections.deque[bytes] = collections.deque(maxlen=self.start_frames * 2)
        voiced: list[bytes] = []
        speaking = False
        silent_run = 0
        voiced_run = 0

        while not self._stop.is_set():
            frame = self._frames.get()
            if frame is None:
                break
            if len(frame) != FRAME_BYTES:
                continue

            if self.muted:
                speaking, silent_run, voiced_run = False, 0, 0
                voiced.clear()
                preroll.clear()
                self.level = 0.0
                continue

            self._track_level(frame)

            try:
                is_speech = self.vad.is_speech(frame, RATE)
            except Exception:  # a malformed frame must not kill the session
                continue

            if is_speech:
                self.last_voice_at = time.monotonic()

            if not speaking:
                preroll.append(frame)
                voiced_run = voiced_run + 1 if is_speech else 0
                if voiced_run >= self.start_frames:
                    speaking = True
                    voiced = list(preroll)
                    silent_run = 0
                    self.loop.call_soon_threadsafe(self.speech_started.set)
                continue

            voiced.append(frame)
            silent_run = silent_run + 1 if not is_speech else 0

            if silent_run >= self.end_frames or len(voiced) >= self.max_frames:
                speaking = False
                voiced_run = 0
                preroll.clear()
                # Trim the trailing silence that proved the utterance ended.
                keep = voiced[: len(voiced) - silent_run] if silent_run else voiced
                if len(keep) >= self.min_frames:
                    self.loop.call_soon_threadsafe(self._emit, b"".join(keep))
                else:
                    log.debug("dropped %d frames of noise", len(keep))
                voiced = []

    def _track_level(self, frame: bytes) -> None:
        """Peak amplitude, smoothed, on a curve that suits a level meter.

        Fast attack and slow release: the bars should jump on a syllable and
        fall back gently, rather than flickering at frame rate.
        """
        peak = audioop_max(frame) / 32768.0
        # Speech sits well below full scale, so a square root spreads the
        # useful range over the meter instead of leaving it near the floor.
        scaled = min(1.0, peak**0.5)
        self.level = scaled if scaled > self.level else self.level * 0.82 + scaled * 0.18

    def _emit(self, pcm: bytes) -> None:
        self.speech_started.clear()
        self.level = 0.0
        self.utterances.put_nowait(Utterance(pcm))


class Player:
    """Plays raw mono PCM, and can be cut off mid-sentence."""

    def __init__(self, rate: int, device: str | int | None = None):
        self.rate = rate
        self.device = device
        self._stream: sd.RawOutputStream | None = None
        self._lock = asyncio.Lock()

    def _ensure(self) -> sd.RawOutputStream:
        if self._stream is None:
            self._stream = sd.RawOutputStream(
                samplerate=self.rate,
                device=self.device,
                channels=1,
                dtype="int16",
            )
            self._stream.start()
        return self._stream

    async def play(self, pcm: bytes, cancelled: asyncio.Event) -> bool:
        """Write PCM in small chunks so a barge-in stops within ~50ms.

        Returns False when playback was cut short.
        """
        async with self._lock:
            stream = self._ensure()
            chunk = self.rate // 20 * 2  # 50ms
            for offset in range(0, len(pcm), chunk):
                if cancelled.is_set():
                    return False
                await asyncio.to_thread(stream.write, pcm[offset : offset + chunk])
            return True

    def close(self) -> None:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
