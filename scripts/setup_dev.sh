#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3.12}"
MODEL_ID="${VERBATIM_PARAKEET_MODEL:-mlx-community/parakeet-tdt_ctc-110m}"
MODEL_CACHE_DIR="${VERBATIM_MODEL_CACHE_DIR:-$HOME/Library/Application Support/Verbatim/Models}"

cd "$ROOT_DIR"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python 3.12 is required. Install it first, then rerun this script."
  exit 1
fi

"$PYTHON_BIN" -m venv venv
venv/bin/python -m pip install --upgrade pip
venv/bin/python -m pip install -r requirements.txt

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required for audio decoding."
  echo "Install with Homebrew: brew install ffmpeg"
  exit 1
fi

MODEL_ID="$MODEL_ID" MODEL_CACHE_DIR="$MODEL_CACHE_DIR" venv/bin/python - <<'PY'
import os
from pathlib import Path
from huggingface_hub import snapshot_download

model_id = os.environ["MODEL_ID"]
cache_dir = Path(os.environ["MODEL_CACHE_DIR"])
cache_dir.mkdir(parents=True, exist_ok=True)
print(f"Downloading {model_id} to {cache_dir}")
snapshot_download(model_id, repo_type="model", cache_dir=cache_dir)
print("Model ready.")
PY

swift build

echo "Setup complete."
