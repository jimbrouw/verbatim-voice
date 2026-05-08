from __future__ import annotations

import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from parakeet_mlx import from_pretrained


MODEL_ID = os.getenv("VERBATIM_PARAKEET_MODEL", "mlx-community/parakeet-tdt_ctc-110m")
MODEL_CACHE_DIR = Path(
    os.getenv(
        "VERBATIM_MODEL_CACHE_DIR",
        str(Path.home() / "Library" / "Application Support" / "Verbatim" / "Models"),
    )
)

app = FastAPI(title="Verbatim Parakeet MLX Helper")

model = None
model_load_error: str | None = None


def configure_ffmpeg_path():
    candidates = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
    ]
    path_parts = os.environ.get("PATH", "").split(os.pathsep)

    for directory in candidates:
        if Path(directory, "ffmpeg").exists() and directory not in path_parts:
            path_parts.insert(0, directory)

    os.environ["PATH"] = os.pathsep.join(part for part in path_parts if part)


def log(message: str):
    try:
        print(message, flush=True)
    except BrokenPipeError:
        try:
            sys.stdout = open(os.devnull, "w")
        except Exception:
            pass


def get_model():
    global model, model_load_error

    if model is not None:
        return model

    MODEL_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    log(f"Initializing Parakeet MLX model: {MODEL_ID}")
    log(f"Model cache: {MODEL_CACHE_DIR}. First run may download a large model.")
    try:
        started_at = time.perf_counter()
        model = from_pretrained(MODEL_ID, cache_dir=MODEL_CACHE_DIR)
        model_load_error = None
        log(f"Parakeet MLX model ready in {time.perf_counter() - started_at:.1f}s.")
        return model
    except Exception as exc:
        model_load_error = str(exc)
        log(f"Parakeet MLX model load failed: {exc}")
        raise


@app.get("/health")
async def health():
    return {
        "ok": model_load_error is None,
        "engine": "parakeet-mlx",
        "model": MODEL_ID,
        "loaded": model is not None,
        "error": model_load_error,
    }


@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    fd, temp_path = tempfile.mkstemp(suffix=".wav")
    started_at = time.perf_counter()

    try:
        with os.fdopen(fd, "wb") as temp_file:
            shutil.copyfileobj(file.file, temp_file)

        log(f"Transcribing file: {temp_path}")
        parakeet = get_model()
        result = parakeet.transcribe(temp_path)
        latency = time.perf_counter() - started_at
        text = result.text.strip()

        log(f"Transcription complete in {latency:.3f}s.")
        return {
            "text": text,
            "latency": latency,
            "engine": "parakeet-mlx",
            "model": MODEL_ID,
        }
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={
                "error": "transcription_failed",
                "message": str(exc),
                "engine": "parakeet-mlx",
                "model": MODEL_ID,
            },
        ) from exc
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == "__main__":
    configure_ffmpeg_path()
    port = int(os.getenv("VERBATIM_MLX_PORT", "8765"))
    uvicorn.run(app, host="127.0.0.1", port=port)
