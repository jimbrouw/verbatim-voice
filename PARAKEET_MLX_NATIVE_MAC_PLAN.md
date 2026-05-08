# [Inference] Verbatim Native Mac Plan: Parakeet MLX Integration

Generated on 2026-05-08 after reviewing the local planning documents and the current Swift/Python bridge.

## Verdict

[Inference] Do not base the native Mac app directly on `EliFuzz/parakeet-mlx` as the committed product dependency.

Use Parakeet MLX as a local ASR direction, but treat the Python ASR service as a replaceable engine behind a stable Swift protocol. The current best path is:

1. Keep the macOS shell native: Swift, SwiftUI, AVFoundation, CGEvent, NSPasteboard.
2. Run ASR in a local helper process during prototype and beta.
3. Use the actively packaged `parakeet-mlx` API that is installed locally from `senstella/parakeet-mlx`, unless the EliFuzz repo is intentionally vendored and its license/API ambiguity is resolved.
4. Keep `whisper.cpp` or SwiftWhisper as a fallback engine until Parakeet quality, latency, packaging, and license posture are verified.

## Evidence Reviewed

Local planning docs:

- `/Users/standard/Developer/Speak_and_spell/PROJECT_PLANNING.md`
- `/Users/standard/Developer/Speak_and_spell/Plan for Verbatim.md`
- `/Users/standard/Developer/Speak_and_spell/verbatim_prd_market_analysis.md`
- `/Users/standard/Developer/Speak_and_spell/docs/plans/2026-04-27-voice-v3-plan.md`
- `/Users/standard/Developer/Speak_and_spell/docs/specs/2026-04-25-voice-v3-design.md`
- `/Users/standard/Developer/Speak_and_spell/voice-v3-todo.md`
- `/Users/standard/Developer/Speak_and_spell/v2_planning_skill.md`
- `/Users/standard/Developer/verbatim-voice/README.md`
- `/Users/standard/Developer/verbatim-voice/Plan for Verbatim.md`
- `/Users/standard/Developer/verbatim-voice/verbatim_prd_market_analysis.md`

Current implementation files:

- `/Users/standard/Developer/verbatim-voice/Package.swift`
- `/Users/standard/Developer/verbatim-voice/AudioManager.swift`
- `/Users/standard/Developer/verbatim-voice/RecordingManager.swift`
- `/Users/standard/Developer/verbatim-voice/MLXTranscriber.swift`
- `/Users/standard/Developer/verbatim-voice/PythonServerManager.swift`
- `/Users/standard/Developer/verbatim-voice/TextInjector.swift`
- `/Users/standard/Developer/verbatim-voice/mlx_server.py`

Upstream sources checked:

- `https://github.com/EliFuzz/parakeet-mlx`
- `https://raw.githubusercontent.com/EliFuzz/parakeet-mlx/main/pyproject.toml`
- `https://raw.githubusercontent.com/EliFuzz/parakeet-mlx/main/LICENSE`
- `https://github.com/senstella/parakeet-mlx`
- `https://dicta.to/blog/whisper-vs-parakeet-vs-apple-speech-engine/`
- `https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3`
- `https://developer.apple.com/documentation/speech/speechanalyzer`

Local environment check:

- `/Users/standard/Developer/verbatim-voice/venv` has `parakeet-mlx 0.5.1`.
- Its package metadata points to `https://github.com/senstella/parakeet-mlx.git`.
- The installed `parakeet_mlx` module exports `from_pretrained`.
- Direct import of `UnifiedTranscriber` and `TranscriptionConfig` fails in this venv.

## Main Problems With The Current Plan

### 1. The project is mixing two different Parakeet MLX APIs

The current `/Users/standard/Developer/verbatim-voice/mlx_server.py` imports:

```python
from parakeet_mlx import UnifiedTranscriber, TranscriptionConfig
```

The installed local package exports `from_pretrained`, matching the `senstella/parakeet-mlx` API. The current server fails at import time in this environment with `ImportError: cannot import name 'UnifiedTranscriber'`.

### 2. `EliFuzz/parakeet-mlx` is not a strong app dependency yet

Verified concerns:

- The GitHub repository showed 2 commits, no releases, 9 stars, and 1 fork at review time.
- GitHub labels the repo license as GPL-3.0 from `LICENSE`.
- `pyproject.toml` declares `license = "Apache-2.0"`.
- The README and `pyproject.toml` describe different maturity signals than the repository size supports.

[Inference] For a paid Mac app, this is too much ambiguity for direct bundling without owner clarification or legal review.

### 3. Python MLX can fit the prototype, but it is not "native" in the strict sense

The Swift app is native at the UI, audio, hotkey, and text injection layers. The ASR layer is currently a local Python HTTP service. That is acceptable for fast iteration, but the product plan should call it what it is: native Mac shell plus local helper process.

### 4. The model setting in `mlx_server.py` is suspicious

The server sets:

```python
config.model_path = "mlx-community/whisper-tiny.en-mlx-q4"
```

[Inference] That looks like a Whisper MLX model name, not a Parakeet TDT model name. This may undercut the goal of evaluating Parakeet.

## Revised Product Direction

Verbatim should stay focused on the lane repeated across the planning docs:

- macOS only first
- private/local by default
- push-to-talk
- system-wide paste
- tiny UI
- no meeting recorder
- no big editor
- no AI rewriting in MVP
- one-time purchase or simple paid upgrade later

[Inference] Parakeet MLX is attractive because it may be faster than Whisper on Apple Silicon, but the MVP should not depend on one ASR engine being perfect. The app should own the workflow; ASR engines should be swappable.

## 2026 Engine Read: Dictato Article

The Dictato article dated 2026-03-08 argues for a three-engine model:

- Parakeet for fastest supported-language dictation.
- Whisper or WhisperKit for broad language support.
- Apple SpeechAnalyzer for zero-download, low-resource macOS 26+ setups.

Useful confirmed details from the article:

- It positions Parakeet at roughly `80ms` on Apple Silicon.
- It positions Whisper at roughly `200-500ms`.
- It positions Apple SpeechAnalyzer at roughly `150-400ms`.
- It says Parakeet is larger on disk, roughly `2.3GB`.
- It says Whisper supports more languages than Parakeet.
- It says SpeechAnalyzer requires macOS 26+.

Important caveat:

- [Unverified] I have not independently reproduced Dictato's latency or accuracy numbers on this M1 machine.
- [Inference] Dictato sells a Mac dictation app, so its benchmarks are useful but should not be the only basis for product architecture.
- The article supports "Parakeet as default engine" more than it supports "EliFuzz/parakeet-mlx as shipped dependency."

Additional source check:

- NVIDIA's `parakeet-tdt-0.6b-v3` Hugging Face page lists the model as CC-BY-4.0 and describes it as a FastConformer-TDT model with 600M parameters, 16kHz mono input, punctuation/capitalization, and 25-language evaluation notes.
- Apple has public SpeechAnalyzer developer documentation, but SpeechAnalyzer is not available for the project's current stated target of macOS 14.

Updated engine strategy:

1. Default beta engine: Parakeet MLX if the local benchmark passes.
2. Fallback engine: WhisperKit or SwiftWhisper for broader language support and lower dependency risk.
3. Future native engine: SpeechAnalyzer for users on macOS 26+.
4. Experimental engines: Moonshine, Canary, Voxtral, and others only after MVP dictation is solid.

## Target Architecture

```text
SwiftUI menu bar app
  |
  |-- HotkeyManager
  |-- AudioManager
  |-- FloatingPillWindow
  |-- TextInjector
  |
  |-- TranscriptionEngine protocol
        |
        |-- ParakeetLocalEngine
        |     Swift HTTP client -> local Python helper
        |
        |-- WhisperFallbackEngine
              SwiftWhisper or whisper.cpp path

Local Python helper
  |
  |-- /health
  |-- /models
  |-- /transcribe
  |-- stderr/stdout logs for diagnostics
```

## Swift Contract

Create a protocol that hides the engine implementation:

```swift
protocol TranscriptionEngine {
    var name: String { get }
    var isReady: Bool { get async }
    func transcribe(audioURL: URL) async throws -> TranscriptionResult
}

struct TranscriptionResult {
    let text: String
    let duration: TimeInterval?
    let engine: String
}
```

[Inference] This reduces churn when switching between Parakeet, Whisper, and future native Core ML/MLX options.

## Python Helper Contract

The helper should expose a tiny local API:

```text
GET  /health
GET  /models
POST /transcribe
```

Expected response:

```json
{
  "text": "transcribed text",
  "duration": 1.23,
  "engine": "parakeet-mlx",
  "model": "mlx-community/parakeet-tdt-0.6b-v3"
}
```

Errors should use non-200 HTTP status codes and a JSON body:

```json
{
  "error": "short readable error",
  "detail": "debug detail for logs"
}
```

## Implementation Plan

### Phase 0: Stop API Drift

- Add `requirements.txt` or `pyproject.toml` to `/Users/standard/Developer/verbatim-voice`.
- Pin the actual Python package source and version.
- Replace `UnifiedTranscriber` usage with the installed `from_pretrained` API, or intentionally vendor the EliFuzz repo and document why.
- Change the model to a real Parakeet model, such as `mlx-community/parakeet-tdt-0.6b-v3`, if using the senstella API.
- Add `GET /health` so Swift can show "engine loading", "ready", or "failed".

### Phase 1: Make The Current App Stable

- Convert `MLXTranscriber.transcribe` to `async throws` instead of callback-only.
- Move hardcoded paths out of `PythonServerManager`.
- Start the helper from the app bundle resources in packaged builds.
- Add startup timeout and health polling.
- Capture helper logs to `~/Library/Logs/Verbatim/`.
- Use a random free localhost port or a single lock file to avoid port collisions.
- Keep the model loaded once per app session.

### Phase 2: Audio Path Cleanup

- Keep recording in AVFoundation.
- Write temporary audio as PCM WAV in a known format.
- Normalize/resample before submitting to the helper if the selected ASR model needs a specific sample rate.
- Add recording guards already present in `RecordingManager`: minimum duration and file size checks.
- Add a post-stop debounce so the stop sound is not recorded into the dictation clip.

### Phase 3: Engine Selection

- Add `TranscriptionEngine` in Swift.
- Implement `ParakeetHTTPTranscriptionEngine`.
- Keep `SwiftWhisper` or `WhisperManager` as fallback until Parakeet passes local tests.
- Add a hidden debug setting to switch engines.
- Log engine, model, audio duration, transcription latency, and error category.

### Phase 4: Packaging

- Bundle a Python runtime only after the prototype is stable.
- Package the helper as one of:
  - [Inference] a signed helper executable built with PyInstaller/Nuitka, or
  - [Inference] a managed embedded venv copied into app resources.
- Place downloaded models under `~/Library/Application Support/Verbatim/Models`.
- Do not redownload models at each launch.
- Add a first-run model download screen only if the model cannot be bundled.

### Phase 5: Quality Bar

Test with short dictations across:

- Notes
- Safari text fields
- Chrome text fields
- Slack
- Messages
- VS Code
- Cursor
- Word or Pages

Measure:

- cold helper startup time
- warm transcription latency
- audio duration
- output accuracy by phrase set
- paste success rate
- clipboard restoration reliability
- CPU and memory while idle
- CPU and memory while transcribing

### Phase 6: Product Scope For Beta

Beta MVP:

- Hold Option to record
- Release to transcribe
- Paste into focused app
- Tiny floating pill
- Local ASR
- Engine/model selector behind advanced settings
- Launch at login
- Permission onboarding
- Diagnostics export

Defer:

- AI rewriting
- meetings
- cloud sync
- command mode
- complex presets
- big transcript dashboard
- Windows support
- iOS port

## Specific File Changes To Make Next

1. `/Users/standard/Developer/verbatim-voice/mlx_server.py`
   - Replace current imports with the installed API.
   - Add `/health`.
   - Return structured errors.
   - Use a verified Parakeet model name.

2. `/Users/standard/Developer/verbatim-voice/PythonServerManager.swift`
   - Remove hardcoded absolute paths.
   - Add readiness polling.
   - Add stderr/stdout log routing.
   - Track helper lifecycle.

3. `/Users/standard/Developer/verbatim-voice/MLXTranscriber.swift`
   - Rename to `ParakeetHTTPTranscriber.swift` or wrap it behind `TranscriptionEngine`.
   - Use `async throws`.
   - Parse non-200 responses.

4. `/Users/standard/Developer/verbatim-voice/RecordingManager.swift`
   - Depend on `TranscriptionEngine`, not `MLXTranscriber` directly.
   - Keep current short-recording and tiny-file guards.

5. `/Users/standard/Developer/verbatim-voice/Package.swift`
   - Remove unused SwiftWhisper later only after fallback strategy is decided.

## Decision Gates

### Gate A: Can Parakeet MLX run locally with acceptable latency?

Run a repeatable benchmark with 10 short clips. Capture p50 and p95 latency. [Inference] If p95 warm latency is above the product feel target, keep Whisper fallback active.

### Gate B: Is the license acceptable?

Do not ship EliFuzz code in a paid app until the GPL-3.0 vs Apache-2.0 conflict is clarified. The installed package currently reports Apache-2.0 and points to senstella, but the app should document the exact dependency source used.

### Gate C: Can packaging be made simple enough?

If Python helper packaging becomes brittle, move back to `whisper.cpp` for the first paid beta and keep Parakeet as an experimental engine.

## Recommendation

[Inference] The right plan is not "use EliFuzz/parakeet-mlx in the native Mac app." The better plan is:

Use a native Swift app with a stable transcription protocol, connect it to a local Parakeet MLX helper for now, verify the senstella package API and model quality, keep Whisper as fallback, and only commit to Parakeet as the default after latency, packaging, and licensing are clean enough for beta distribution.
