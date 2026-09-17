#!/usr/bin/env bash
# Builds the venv for the dictation server and warms the model cache.
# Safe to re-run; re-running is also how you switch WHISPER_MODEL.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
model=${WHISPER_MODEL:-large-v3}

# 3.12 rather than the system 3.14: ctranslate2 publishes no wheel for 3.14 yet.
uv venv --python 3.12 "$here/.venv"

# Arch's CUDA is 13; the ctranslate2 wheels want cuBLAS 12 and cuDNN 9, so the
# venv carries its own. server.py dlopens them before importing ctranslate2.
uv pip install --python "$here/.venv/bin/python" --quiet \
    faster-whisper numpy nvidia-cublas-cu12 nvidia-cudnn-cu12

echo "downloading model $model (a few GB the first time)…"
WHISPER_MODEL="$model" "$here/.venv/bin/python" - <<'PY'
import os
from faster_whisper import WhisperModel
WhisperModel(os.environ["WHISPER_MODEL"], device="cpu", compute_type="int8")
print("model cached")
PY

echo
echo "done. Start it with:"
echo "  systemctl --user enable --now whisper-dictate.service"
