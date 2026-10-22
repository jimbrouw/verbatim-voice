from __future__ import annotations

import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

try:
    from parakeet_mlx import from_pretrained
except ImportError:
    from_pretrained = None

try:
    from mlx_lm import generate, load
    from mlx_lm.sample_utils import make_sampler
except ImportError:
    generate = None
    load = None
    make_sampler = None


MODEL_ID = os.getenv("VOICE_PARAKEET_MODEL", os.getenv("VERBATIM_PARAKEET_MODEL", "mlx-community/parakeet-tdt_ctc-110m"))
LLM_MODEL_ID = os.getenv("VOICE_LLM_MODEL", os.getenv("VERBATIM_LLM_MODEL", "mlx-community/Llama-3.2-1B-Instruct-4bit"))

MODEL_CACHE_DIR = Path(
    os.getenv(
        "VOICE_MODEL_CACHE_DIR",
        os.getenv(
            "VERBATIM_MODEL_CACHE_DIR",
            str(Path.home() / "Library" / "Application Support" / "Voice&" / "Models"),
        ),
    )
)

app = FastAPI(title="Voice& Parakeet + Llama MLX Helper")

model = None
model_load_error: str | None = None

llm_model = None
llm_tokenizer = None
llm_load_error: str | None = None


DYSLEXIA_PROMPT_TEMPLATE = """You are a cognitive translation assistant for a dyslexic thinker.
Your job is to strip out academic jargon, tech buzzwords, and fluff, and explain the core point in direct, punchy, plain English.

Input Text:
\"\"\"
{text}
\"\"\"

Format your response exactly like this:
TL;DR: [1 clear sentence explaining what this actually means in real life]

KEY POINTS:
• [Action or fact 1]
• [Action or fact 2]
• [Action or fact 3 if applicable]"""


class SummarizeRequest(BaseModel):
    text: str = Field(..., description="The raw selected text to summarize in plain English")
    max_tokens: int = Field(300, description="Maximum tokens to generate")
    temperature: float = Field(0.1, description="Sampling temperature")


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

    if from_pretrained is None:
        raise RuntimeError("parakeet_mlx is not installed in the environment.")

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


def get_llm_model():
    global llm_model, llm_tokenizer, llm_load_error

    if llm_model is not None and llm_tokenizer is not None:
        return llm_model, llm_tokenizer

    if load is None:
        raise RuntimeError("mlx_lm is not installed in the environment.")

    MODEL_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    log(f"Initializing Voice& Plain-English LLM: {LLM_MODEL_ID}")
    try:
        started_at = time.perf_counter()
        llm_model, llm_tokenizer = load(LLM_MODEL_ID)
        llm_load_error = None
        log(f"Voice& Plain-English LLM ready in {time.perf_counter() - started_at:.1f}s.")
        return llm_model, llm_tokenizer
    except Exception as exc:
        llm_load_error = str(exc)
        log(f"Voice& Plain-English LLM load failed: {exc}")
        raise


def parse_summary_response(text: str) -> tuple[str, list[str]]:
    """
    Parses structured TL;DR and Key Points from the LLM output.
    Gracefully handles slight formatting drift.
    """
    tldr = ""
    points: list[str] = []
    lines = [line.strip() for line in text.strip().splitlines() if line.strip()]

    in_key_points = False
    for line in lines:
        upper = line.upper()
        if upper.startswith("TL;DR:") or upper.startswith("TLDR:"):
            prefix_len = len("TL;DR:") if upper.startswith("TL;DR:") else len("TLDR:")
            tldr = line[prefix_len:].strip()
        elif upper.startswith("KEY POINTS:") or upper.startswith("KEY TAKEAWAYS:"):
            in_key_points = True
        elif in_key_points:
            cleaned = line.lstrip("•-* \t0123456789.)").strip()
            if cleaned:
                points.append(cleaned)
        elif not tldr and not in_key_points:
            tldr = line

    if not tldr and points:
        tldr = points[0]
        points = points[1:]

    return tldr, points


@app.get("/health")
async def health():
    return {
        "ok": (model_load_error is None) and (llm_load_error is None),
        "app": "Voice&",
        "engine": "parakeet-mlx + mlx-lm",
        "stt_model": MODEL_ID,
        "llm_model": LLM_MODEL_ID,
        "stt_loaded": model is not None,
        "llm_loaded": llm_model is not None,
        "stt_error": model_load_error,
        "llm_error": llm_load_error,
    }


@app.post("/summarize")
async def summarize_text(req: SummarizeRequest):
    input_text = req.text.strip()
    if not input_text:
        raise HTTPException(status_code=400, detail="Input text cannot be empty.")

    started_at = time.perf_counter()
    try:
        loaded_model, tokenizer = get_llm_model()
        user_prompt = DYSLEXIA_PROMPT_TEMPLATE.format(text=input_text)

        if hasattr(tokenizer, "apply_chat_template") and tokenizer.chat_template:
            messages = [{"role": "user", "content": user_prompt}]
            prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        else:
            prompt = user_prompt

        sampler = make_sampler(req.temperature) if make_sampler else None
        generated = generate(
            loaded_model,
            tokenizer,
            prompt=prompt,
            max_tokens=req.max_tokens,
            sampler=sampler,
            verbose=False,
        )
        latency = time.perf_counter() - started_at
        tldr, key_points = parse_summary_response(generated)

        log(f"Summarization complete in {latency:.3f}s.")
        return {
            "tldr": tldr,
            "key_points": key_points,
            "raw": generated.strip(),
            "latency": latency,
            "model": LLM_MODEL_ID,
        }
    except Exception as exc:
        log(f"Summarization error: {exc}")
        raise HTTPException(
            status_code=500,
            detail={
                "error": "summarization_failed",
                "message": str(exc),
                "model": LLM_MODEL_ID,
            },
        ) from exc


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
    port = int(os.getenv("VOICE_MLX_PORT", os.getenv("VERBATIM_MLX_PORT", "8768")))
    uvicorn.run(app, host="127.0.0.1", port=port)
