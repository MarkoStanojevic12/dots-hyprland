#!/usr/bin/env python3
"""Speech-to-text for the Claude sidebar's dictation button.

Takes raw 16 kHz mono s16le PCM on POST /transcribe and answers with the
transcript as text/plain. Runs on 127.0.0.1 only — nothing leaves the machine.

/stream/start, /stream/chunk?id=, /stream/end?id= drive a LocalAgreement-2 live
decoder (see streaming.py) so the sidebar can show words while they are being
said, and /stream/end returns the transcript — POST /transcribe is now only the
fallback for when streaming is unavailable.

Both accept ?model= to switch between the ids in WHISPER_MODELS, which is what
the sidebar's right-click picker uses. GET /models lists them, marking the
current one with a leading "* ".

Settings come from the environment (see whisper-dictate.service):
  WHISPER_MODEL    faster-whisper model id            (default large-v3)
  WHISPER_MODELS   comma-separated ids the picker may switch to
  WHISPER_DEVICE   cuda | cpu | auto                  (default auto)
  WHISPER_COMPUTE  float16 | int8_float16 | int8, empty = pick per device
  WHISPER_PORT     port to listen on                  (default 8765)
  WHISPER_LANG     language code, empty = autodetect  (default en)
  WHISPER_IDLE     seconds before the model is unloaded from VRAM (0 = never)
  WHISPER_PROMPT   vocabulary hint for the decoder
  WHISPER_STREAM_MIN   seconds of audio a live chunk needs before it decodes
  WHISPER_STREAM_TRIM  seconds a live session re-decodes before trimming
  WHISPER_LOAD_WAIT    seconds /transcribe waits for weights still loading

Weights load on a background thread, so a cold model answers /stream/chunk with
202 and the name it is loading instead of blocking. Run `server.py --prefetch`
to pull every id in WHISPER_MODELS down first and avoid that entirely.
"""

import ctypes
import gc
import glob
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

MODEL = os.environ.get("WHISPER_MODEL", "large-v3")
# What the sidebar's model picker is allowed to ask for. A name outside this
# list is rejected rather than handed to huggingface, so a typo cannot start a
# multi-gigabyte download.
MODELS = [
    name.strip()
    for name in os.environ.get(
        "WHISPER_MODELS",
        "tiny.en,base.en,small.en,medium.en,distil-large-v3,large-v3-turbo,large-v3",
    ).split(",")
    if name.strip()
]
DEVICE = os.environ.get("WHISPER_DEVICE", "auto")
COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE", "").strip()
PORT = int(os.environ.get("WHISPER_PORT", "8765"))
LANGUAGE = os.environ.get("WHISPER_LANG", "en").strip()
IDLE_UNLOAD = float(os.environ.get("WHISPER_IDLE", "900"))
# Project names and jargon belong in WHISPER_PROMPT in the service unit, not
# here — this file is public and that list is not.
PROMPT = os.environ.get("WHISPER_PROMPT", "").strip()

SAMPLE_RATE = 16000
MIN_SAMPLES = SAMPLE_RATE // 5  # under 0.2 s is a misclick, not speech

# Below this the decode costs more than the words it would add.
STREAM_MIN_SECONDS = float(os.environ.get("WHISPER_STREAM_MIN", "1.0"))
# How much audio a live session re-decodes before it trims at a committed
# segment boundary. Higher is more accurate and slower per chunk.
STREAM_TRIM_SECONDS = float(os.environ.get("WHISPER_STREAM_TRIM", "15"))
# How long a caller that cannot give up (the one-shot /transcribe) waits for
# weights that are still loading.
LOAD_WAIT_SECONDS = float(os.environ.get("WHISPER_LOAD_WAIT", "300"))

# huggingface's xet client has no read timeout, so a transfer that stalls at
# zero bytes never raises — one did, and it held the model lock until the
# service was restarted. The plain HTTP path honours the timeouts below.
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "20")
os.environ.setdefault("HF_HUB_ETAG_TIMEOUT", "10")


def preload_cuda_libraries():
    """Make the pip-installed CUDA 12 libs visible to ctranslate2.

    Arch ships CUDA 13 (libcublas.so.13) but the ctranslate2 wheels link
    against .so.12 and cuDNN 9, so the venv carries its own copies. The loader
    only reads LD_LIBRARY_PATH at exec time, so they are dlopen'd by hand here
    instead — two passes, because cuDNN needs cuBLAS resolved first.
    """
    patterns = [
        os.path.join(prefix, "nvidia", "*", "lib", "*.so*")
        for prefix in glob.glob(os.path.join(sys.prefix, "lib", "python*", "site-packages"))
    ]
    libraries = sorted({path for pattern in patterns for path in glob.glob(pattern)})
    for _ in range(2):
        pending = []
        for path in libraries:
            try:
                ctypes.CDLL(path, mode=ctypes.RTLD_GLOBAL)
            except OSError:
                pending.append(path)
        if not pending:
            break
        libraries = pending


preload_cuda_libraries()

import numpy as np  # noqa: E402  — after the CUDA preload
from faster_whisper import WhisperModel  # noqa: E402

import streaming  # noqa: E402


class ModelLoading(Exception):
    """The weights are not in memory yet. Stringifies to the model being loaded."""


class Transcriber:
    def __init__(self):
        self._lock = threading.Lock()
        self._model = None
        self._device = None
        self._name = MODEL
        self._loading = ""
        self._load_error = ""
        self._last_used = time.monotonic()

    @property
    def loaded(self):
        return self._model is not None

    @property
    def loading(self):
        return self._loading

    @property
    def device(self):
        return self._device

    @property
    def name(self):
        return self._name

    def use_model(self, name):
        """Switch models, loading the new one lazily on the next decode.

        Dropping the weights here rather than loading eagerly matters on a card
        that is already shared — the old model's VRAM is freed before anything
        asks for the new one's.
        """
        if not name or name == self._name:
            return
        if name not in MODELS:
            raise ValueError(f"unknown model {name!r}")
        with self._lock:
            if name == self._name:
                return
            log(f"switching model {self._name} -> {name}")
            self._name = name
            self._model = None
            self._device = None
            self._loading = ""
            self._load_error = ""
            gc.collect()

    def ensure_loaded(self):
        """Start the load in the background; raise ModelLoading until it lands.

        A first use of an uncached model downloads gigabytes inside _load, and
        holding the lock across that wedges every other request — a stalled
        transfer once took the whole server with it. Callers that can afford to
        wait say so; the live previews would rather come back empty.
        """
        with self._lock:
            if self._model is not None:
                return
            if self._load_error:
                error, self._load_error = self._load_error, ""
                raise RuntimeError(error)
            if not self._loading:
                self._loading = self._name
                threading.Thread(target=self._load_into, args=(self._name,), daemon=True).start()
            raise ModelLoading(self._loading)

    def _load_into(self, name):
        try:
            model, device = self._load(name)
        except Exception as error:
            log(f"could not load {name}: {error}")
            with self._lock:
                if self._loading == name:
                    self._loading = ""
                    self._load_error = str(error)
            return
        with self._lock:
            if self._name != name:  # switched away mid-load; the download is cached now
                if self._loading == name:
                    self._loading = ""
                return
            self._model, self._device = model, device
            self._loading = ""
            self._last_used = time.monotonic()

    def _load(self, name):
        # int8_float16 before the CPU: it is a third of the VRAM of float16 for
        # a barely measurable accuracy cost, which is what gets the model in
        # next to whatever else already has the card.
        ladder = {
            "auto": [("cuda", "float16"), ("cuda", "int8_float16"), ("cpu", "int8")],
            "cuda": [("cuda", "float16"), ("cuda", "int8_float16")],
            "cpu": [("cpu", "int8")],
        }
        candidates = ladder.get(DEVICE) or [(DEVICE, COMPUTE_TYPE or "int8")]
        if COMPUTE_TYPE:
            candidates = [(device, COMPUTE_TYPE) for device, _ in candidates]
        errors = []
        for device, compute_type in candidates:
            try:
                started = time.monotonic()
                model = WhisperModel(name, device=device, compute_type=compute_type)
                log(f"loaded {name} on {device}/{compute_type} in {time.monotonic() - started:.1f}s")
                return model, device
            except Exception as error:  # a full card or a library mismatch must not be fatal
                errors.append(f"{device}/{compute_type}: {error}")
                log(f"could not load on {device}/{compute_type}: {error}")
                gc.collect()
        raise RuntimeError("; ".join(errors))

    def transcribe(self, audio, language):
        # The one-shot pass is the fallback for when the live stream came back
        # empty, so waiting out a download beats losing the recording.
        return self._guarded(lambda: self._run(audio, language), wait=True)

    def transcribe_words(self, audio, language, init_prompt):
        """Word-timestamped segments for the streaming decoder.

        Same model and lock as the final pass, so a live session and the
        one-shot transcribe serialise against each other instead of trying to
        share the decoder.
        """
        return self._guarded(lambda: self._run_words(audio, language, init_prompt))

    def _guarded(self, work, wait=False):
        deadline = time.monotonic() + LOAD_WAIT_SECONDS
        while True:
            try:
                self.ensure_loaded()
                break
            except ModelLoading:
                if not wait:
                    raise
                if time.monotonic() > deadline:
                    raise RuntimeError(f"timed out loading {self._name}")
                time.sleep(0.2)
        with self._lock:
            if self._model is None:  # the idle reaper got in between
                raise ModelLoading(self._loading or self._name)
            self._last_used = time.monotonic()
            try:
                return work()
            except Exception as error:
                # The card is shared with whatever else is running, so it can
                # fit the weights at load and still have no room for a cuBLAS
                # workspace a minute later. Dropping to the CPU beats losing
                # what was just dictated.
                if self._device != "cuda":
                    raise
                log(f"cuda inference failed ({error}); retrying on the cpu")
                self._model = None
                gc.collect()
                self._model = WhisperModel(self._name, device="cpu", compute_type="int8")
                self._device = "cpu"
                return work()

    def _run(self, audio, language):
        segments, _ = self._model.transcribe(
            audio,
            language=language or None,
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
            initial_prompt=PROMPT or None,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()
        self._last_used = time.monotonic()
        return text

    def _run_words(self, audio, language, init_prompt):
        # beam_size 1: a partial is thrown away the moment the next one lands,
        # so the decode has to keep up with speech, not win on accuracy.
        # temperature 0 for the same reason — the default is a six-step
        # fallback ladder that re-decodes a window whose compression ratio or
        # logprob looks off, and a half-spoken window often does.
        segments, _ = self._model.transcribe(
            audio,
            language=language or None,
            beam_size=1,
            temperature=0,
            word_timestamps=True,
            vad_filter=True,
            condition_on_previous_text=False,
            initial_prompt=(init_prompt or PROMPT) or None,
        )
        segments = list(segments)
        self._last_used = time.monotonic()
        return segments

    def unload_when_idle(self):
        while True:
            time.sleep(30)
            sessions.reap()
            with self._lock:
                if self._model is None or IDLE_UNLOAD <= 0:
                    continue
                if time.monotonic() - self._last_used < IDLE_UNLOAD:
                    continue
                self._model = None
                self._device = None
                log(f"unloaded after {IDLE_UNLOAD:.0f}s idle")


def log(message):
    print(f"whisper-dictate: {message}", file=sys.stderr, flush=True)


transcriber = Transcriber()


class Session:
    def __init__(self, language):
        self.processor = streaming.OnlineASRProcessor(
            streaming.TranscriberASR(transcriber, language),
            buffer_trimming_sec=STREAM_TRIM_SECONDS,
        )
        self.touched = time.monotonic()
        self.chunks = 0


class SessionStore:
    """Live streaming sessions, one per press of the dictate button."""

    STALE_AFTER = 600

    def __init__(self):
        self._lock = threading.Lock()
        self._sessions = {}
        self._next_id = 0

    def start(self, language):
        with self._lock:
            self._next_id += 1
            session_id = str(self._next_id)
            self._sessions[session_id] = Session(language)
        self.reap()
        return session_id

    def get(self, session_id):
        with self._lock:
            session = self._sessions.get(session_id)
            if session is not None:
                session.touched = time.monotonic()
            return session

    def drop(self, session_id):
        with self._lock:
            return self._sessions.pop(session_id, None)

    def reap(self):
        # A sidebar crash or a killed recorder leaves the session behind; its
        # audio buffer is bounded but the object never would be.
        now = time.monotonic()
        with self._lock:
            stale = [k for k, v in self._sessions.items() if now - v.touched > self.STALE_AFTER]
            for key in stale:
                del self._sessions[key]
        if stale:
            log(f"dropped {len(stale)} stale streaming session(s)")


sessions = SessionStore()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def _reply(self, status, body, content_type="text/plain; charset=utf-8"):
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/models":
            self._reply(200, "\n".join(
                ("* " if name == transcriber.name else "") + name for name in MODELS))
            return
        if path != "/health":
            self._reply(404, "not found")
            return
        if transcriber.loading:
            state = f"loading {transcriber.loading}"
        else:
            state = f"{'loaded' if transcriber.loaded else 'idle'} {transcriber.name} {transcriber.device or ''}".strip()
        self._reply(200, state)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def do_POST(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path.startswith("/stream/"):
            self._do_stream(parsed.path, query)
            return

        if parsed.path != "/transcribe":
            self._reply(404, "not found")
            return

        data = self._body()
        if not self._select_model(query):
            return
        audio = np.frombuffer(data, dtype=np.int16)
        if audio.size < MIN_SAMPLES:
            self._reply(400, "Nothing recorded — check the input device")
            return

        language = (query.get("lang") or [LANGUAGE])[0]
        started = time.monotonic()
        try:
            text = transcriber.transcribe(audio.astype(np.float32) / 32768.0, language)
        except Exception as error:
            log(f"transcribe failed: {error}")
            self._reply(500, str(error))
            return

        seconds = audio.size / SAMPLE_RATE
        log(f"{seconds:.1f}s audio in {time.monotonic() - started:.1f}s -> {len(text)} chars")
        self._reply(200, text)

    def _select_model(self, query):
        """Honour ?model= before any decoding. False means a reply was sent."""
        try:
            transcriber.use_model((query.get("model") or [""])[0].strip())
            return True
        except ValueError as error:
            self._reply(400, str(error))
            return False

    def _do_stream(self, path, query):
        action = path[len("/stream/"):]

        if action == "start":
            self._body()  # drain, the connection is kept alive
            if not self._select_model(query):
                return
            # Kick the load off here so it overlaps with the first second of
            # speech rather than stalling the first preview.
            try:
                transcriber.ensure_loaded()
            except Exception:
                pass
            language = (query.get("lang") or [LANGUAGE])[0]
            self._reply(200, sessions.start(language))
            return


        if action not in ("chunk", "end"):
            self._body()
            self._reply(404, "not found")
            return

        session_id = (query.get("id") or [""])[0]
        session = sessions.get(session_id) if action == "chunk" else sessions.drop(session_id)
        data = self._body()
        if session is None:
            self._reply(404, "no such session")
            return
        processor = session.processor

        if action == "chunk":
            session.chunks += 1
            audio = np.frombuffer(data, dtype=np.int16)
            if audio.size:
                processor.insert_audio_chunk(audio.astype(np.float32) / 32768.0)
            if processor.buffered_seconds < STREAM_MIN_SECONDS:
                self._reply(200, processor.text())
                return
            try:
                started = time.monotonic()
                window = processor.buffered_seconds
                text = processor.process_iter()
                log(f"stream {session_id} chunk {session.chunks}: "
                    f"{window:.1f}s window in {(time.monotonic() - started) * 1000:.0f}ms")
                self._reply(200, text)
            except ModelLoading as loading:
                # The audio is already in the processor, so skipping this decode
                # loses nothing — the next chunk picks the backlog up.
                self._reply(202, str(loading))
            except Exception as error:
                log(f"stream chunk failed: {error}")
                self._reply(500, str(error))
            return

        audio = np.frombuffer(data, dtype=np.int16)
        if audio.size:
            processor.insert_audio_chunk(audio.astype(np.float32) / 32768.0)
        started = time.monotonic()
        try:
            text = processor.finalize()
        except ModelLoading:
            # Nothing was ever decoded, so there is no transcript to hand back.
            # The caller still holds the recording and falls back to /transcribe.
            log(f"stream {session_id}: finished while {transcriber.loading} was still loading")
            self._reply(200, processor.text())
            return
        except Exception as error:
            log(f"stream finalize failed: {error}")
            self._reply(500, str(error))
            return
        log(f"stream {session_id}: {session.chunks} chunk(s), "
            f"finalized in {(time.monotonic() - started) * 1000:.0f}ms -> {len(text)} chars")
        self._reply(200, text)


def prefetch():
    """Download every id in MODELS so that no first use is a stalled request."""
    from faster_whisper.utils import download_model

    for name in MODELS:
        started = time.monotonic()
        try:
            download_model(name)
            log(f"fetched {name} in {time.monotonic() - started:.0f}s")
        except Exception as error:
            log(f"could not fetch {name}: {error}")


def main():
    if "--prefetch" in sys.argv:
        prefetch()
        return
    threading.Thread(target=transcriber.unload_when_idle, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    log(f"listening on 127.0.0.1:{PORT}, model {MODEL}, device {DEVICE}")
    server.serve_forever()


if __name__ == "__main__":
    main()
