"""LocalAgreement-2 streaming decoder on top of a faster-whisper model.

Derived from ufal/whisper_streaming (MIT) — `HypothesisBuffer` and
`OnlineASRProcessor` keep their original algorithm. Trimmed to what the
dictation server needs: no file loading, no sentence tokenizer, no CLI, so the
only dependency is numpy plus the already-loaded model.

The idea: re-decode a growing audio buffer every chunk and only treat a word as
final once two consecutive decodes agree on it. Agreed words are committed and
their audio is dropped from the buffer, which bounds the per-chunk cost.
"""

import numpy as np

SAMPLING_RATE = 16000


class HypothesisBuffer:
    def __init__(self):
        self.commited_in_buffer = []
        self.buffer = []
        self.new = []
        self.last_commited_time = 0
        self.last_commited_word = None

    def insert(self, new, offset):
        new = [(a + offset, b + offset, t) for a, b, t in new]
        self.new = [(a, b, t) for a, b, t in new if a > self.last_commited_time - 0.1]

        if len(self.new) >= 1:
            a, _, _ = self.new[0]
            if abs(a - self.last_commited_time) < 1 and self.commited_in_buffer:
                # Drop an n-gram (up to 5 words) that the new hypothesis repeats
                # from the end of what is already committed.
                cn = len(self.commited_in_buffer)
                nn = len(self.new)
                for i in range(1, min(cn, nn, 5) + 1):
                    c = " ".join(self.commited_in_buffer[-j][2] for j in range(1, i + 1)[::-1])
                    tail = " ".join(self.new[j - 1][2] for j in range(1, i + 1))
                    if c == tail:
                        for _ in range(i):
                            self.new.pop(0)
                        break

    def flush(self):
        """Commit the longest common prefix of the last two hypotheses."""
        commit = []
        while self.new and self.buffer:
            na, nb, nt = self.new[0]
            if nt != self.buffer[0][2]:
                break
            commit.append((na, nb, nt))
            self.last_commited_word = nt
            self.last_commited_time = nb
            self.buffer.pop(0)
            self.new.pop(0)
        self.buffer = self.new
        self.new = []
        self.commited_in_buffer.extend(commit)
        return commit

    def pop_commited(self, time):
        while self.commited_in_buffer and self.commited_in_buffer[0][1] <= time:
            self.commited_in_buffer.pop(0)

    def complete(self):
        return self.buffer


class OnlineASRProcessor:
    def __init__(self, asr, buffer_trimming_sec=15.0):
        self.asr = asr
        self.buffer_trimming_sec = buffer_trimming_sec
        self.init()

    def init(self):
        self.audio_buffer = np.array([], dtype=np.float32)
        self.transcript_buffer = HypothesisBuffer()
        self.buffer_time_offset = 0.0
        self.commited = []

    def insert_audio_chunk(self, audio):
        self.audio_buffer = np.append(self.audio_buffer, audio)

    @property
    def buffered_seconds(self):
        return len(self.audio_buffer) / SAMPLING_RATE

    def prompt(self):
        """A 200-character suffix of the text whose audio has been trimmed away."""
        k = max(0, len(self.commited) - 1)
        while k > 0 and self.commited[k - 1][1] > self.buffer_time_offset:
            k -= 1
        words = [t for _, _, t in self.commited[:k]]
        prompt = []
        length = 0
        while words and length < 200:
            word = words.pop(-1)
            length += len(word) + 1
            prompt.append(word)
        return self.asr.sep.join(prompt[::-1])

    def process_iter(self):
        res = self.asr.transcribe(self.audio_buffer, init_prompt=self.prompt())
        self.transcript_buffer.insert(self.asr.ts_words(res), self.buffer_time_offset)
        o = self.transcript_buffer.flush()
        self.commited.extend(o)

        if self.buffered_seconds > self.buffer_trimming_sec:
            self.chunk_completed_segment(res)
            self.enforce_buffer_limit()

        return self.text()

    def enforce_buffer_limit(self):
        """Bound the re-decoded window even when segment trimming cannot run.

        chunk_completed_segment needs two segments to cut between, and speaking
        without a pause gives whisper exactly one — so on its own the buffer,
        and with it the cost of every preview, grows with the length of the
        recording. Cut at the last committed word instead, or failing that at
        whatever keeps the window inside the limit.
        """
        if self.buffered_seconds <= self.buffer_trimming_sec:
            return
        floor = self.buffer_time_offset + self.buffered_seconds - self.buffer_trimming_sec
        last_commited = self.commited[-1][1] if self.commited else 0.0
        self.chunk_at(max(last_commited, floor))

    def text(self):
        """Everything heard so far: committed words plus the unconfirmed tail.

        The tail is included on purpose — this feeds a greyed preview that a
        final pass replaces, so latency matters more than being right.
        """
        words = self.commited + self.transcript_buffer.complete()
        return self.asr.sep.join(t for _, _, t in words).strip()

    def chunk_completed_segment(self, res):
        if not self.commited:
            return
        ends = self.asr.segments_end_ts(res)
        t = self.commited[-1][1]
        if len(ends) <= 1:
            return
        e = ends[-2] + self.buffer_time_offset
        while len(ends) > 2 and e > t:
            ends.pop(-1)
            e = ends[-2] + self.buffer_time_offset
        if e <= t:
            self.chunk_at(e)

    def chunk_at(self, time):
        self.transcript_buffer.pop_commited(time)
        # Keep a little committed context for insert()'s overlap check. Whisper
        # hands back collapsed word timestamps — a whole run of words can share
        # one start == end — so popping strictly by end time discards the very
        # words the next decode repeats, and the repeat then has nothing to be
        # matched against. That is how every transcript used to end by saying
        # its last word twice.
        if not self.transcript_buffer.commited_in_buffer:
            self.transcript_buffer.commited_in_buffer = self.commited[-5:]
        cut_seconds = time - self.buffer_time_offset
        self.audio_buffer = self.audio_buffer[int(cut_seconds * SAMPLING_RATE):]
        self.buffer_time_offset = time

    def finalize(self):
        """Decode the audio that arrived after the last preview, and no more.

        Trimming to the last committed word first keeps this to the leftover
        second or two instead of the whole window: everything before it is
        already in `commited`, and prompt() carries that text into the decode
        as context.

        The cut is at that word's start, not its end, so the re-decode has the
        whole word to work from rather than its tail.
        """
        latest = self.buffer_time_offset + self.buffered_seconds
        if self.commited:
            self.chunk_at(max(self.buffer_time_offset, min(self.commited[-1][0], latest)))

        if self.buffered_seconds > 0.1:
            res = self.asr.transcribe(self.audio_buffer, init_prompt=self.prompt())
            self.transcript_buffer.insert(self.asr.ts_words(res), self.buffer_time_offset)
            self.commited.extend(self.transcript_buffer.flush())

        return self.text()


class TranscriberASR:
    """Adapts the server's shared Transcriber to what OnlineASRProcessor wants."""

    sep = ""  # faster-whisper words already carry their leading space

    def __init__(self, transcriber, language):
        self.transcriber = transcriber
        self.language = language

    def transcribe(self, audio, init_prompt=""):
        return self.transcriber.transcribe_words(audio, self.language, init_prompt)

    def ts_words(self, segments):
        out = []
        for segment in segments:
            if segment.no_speech_prob > 0.9:
                continue
            for word in segment.words or ():
                out.append((word.start, word.end, word.word))
        return out

    def segments_end_ts(self, segments):
        return [s.end for s in segments]
