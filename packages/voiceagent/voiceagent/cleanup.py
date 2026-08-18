"""Tidy a raw transcript before it is typed anywhere.

Even a strong acoustic model returns a run-on, uncapitalised sentence with the
occasional homophone. A fast model fixes punctuation, casing and obvious
mishearings without changing the words, which is most of the distance between
"a transcript" and something you would have typed.

The instructions have to be the *system* prompt with the transcript as the user
message. Passing them positionally makes Claude read the transcript as a
question and answer it, so "what time is it in Tokyo" comes back as an answer
rather than a tidied sentence.
"""

from __future__ import annotations

import asyncio
import logging

log = logging.getLogger("voiceagent.cleanup")

SYSTEM_PROMPT = (
    "You are a dictation post-processor. The user message is a raw "
    "speech-to-text transcript. Return ONLY the corrected text, with no "
    "preamble, quotes, or commentary. Fix punctuation, capitalisation, and "
    "obvious speech-recognition errors. Keep the wording and register; never "
    "summarise, answer, translate, or add anything. If it is already clean, "
    "return it unchanged."
)


class Cleaner:
    def __init__(self, config):
        self.enabled = config.cleanup
        self.model = config.cleanup_model
        self.timeout = config.cleanup_timeout

    async def clean(self, text: str) -> str:
        """Return the tidied transcript, or the original on any failure.

        Never worth failing a dictation over: a raw transcript in the right
        window beats nothing at all.
        """
        if not self.enabled or not text.strip():
            return text

        argv = [
            "claude",
            "-p",
            "--model",
            self.model,
            "--output-format",
            "text",
            "--permission-mode",
            "dontAsk",
            "--disallowed-tools",
            "*",
            "--append-system-prompt",
            SYSTEM_PROMPT,
        ]

        try:
            process = await asyncio.create_subprocess_exec(
                *argv,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            out, err = await asyncio.wait_for(
                process.communicate(text.encode("utf-8")), timeout=self.timeout
            )
        except TimeoutError:
            log.warning("cleanup timed out after %.0fs, using the raw transcript", self.timeout)
            return text
        except (OSError, FileNotFoundError) as exc:
            log.warning("cleanup unavailable (%s), using the raw transcript", exc)
            return text

        if process.returncode:
            log.warning("cleanup failed: %s", err.decode("utf-8", "replace").strip()[:200])
            return text

        cleaned = out.decode("utf-8", "replace").strip()
        if not cleaned:
            return text

        # A model that decides to explain itself would otherwise get typed into
        # the document. Anything wildly longer than the input is not a cleanup.
        if len(cleaned) > max(120, len(text) * 3):
            log.warning("cleanup returned something too long to be a correction; ignoring it")
            return text

        return cleaned
