"""Speech to text against the shared whisper-server.

The same server transcribes dictation for voxtype, so the model is loaded once
for both. It is reached over HTTP rather than linked in, which keeps this
daemon free of the whisper.cpp build and lets the server restart underneath it.
"""

from __future__ import annotations

import io
import logging
import wave

import aiohttp

from .audio import RATE

log = logging.getLogger("voiceagent.stt")


def to_wav(pcm: bytes) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm)
    return buffer.getvalue()


class Transcriber:
    def __init__(self, endpoint: str, timeout: float = 60.0):
        # whisper-server is configured with --inference-path
        # /v1/audio/transcriptions so that voxtype, which hard-codes that path,
        # can share it. Use the same path here.
        self.url = endpoint.rstrip("/") + "/v1/audio/transcriptions"
        self.timeout = aiohttp.ClientTimeout(total=timeout)

    async def transcribe(self, pcm: bytes) -> str:
        form = aiohttp.FormData()
        form.add_field("file", to_wav(pcm), filename="audio.wav", content_type="audio/wav")
        form.add_field("response_format", "json")
        form.add_field("temperature", "0.0")

        try:
            async with aiohttp.ClientSession(timeout=self.timeout) as session:
                async with session.post(self.url, data=form) as response:
                    if response.status != 200:
                        log.error("whisper-server returned %d", response.status)
                        return ""
                    payload = await response.json(content_type=None)
        except aiohttp.ClientError as exc:
            log.error("whisper-server unreachable: %s", exc)
            return ""
        except TimeoutError:
            log.error("whisper-server timed out")
            return ""

        return (payload.get("text") or "").strip()
