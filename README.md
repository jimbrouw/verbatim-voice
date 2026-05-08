# Verbatim Voice

Minimal, private Mac dictation for Apple Silicon.

## What It Does

- Hold Option to record, release to transcribe and paste.
- Double-tap Option for hands-free recording.
- Tap Option once while hands-free to stop, transcribe, and paste.
- Runs transcription locally with Parakeet MLX.

## Current Engine

Default model:

```text
mlx-community/parakeet-tdt_ctc-110m
```

The model is stored outside the app:

```text
~/Library/Application Support/Verbatim/Models
```

## Developer Setup

```bash
scripts/setup_dev.sh
```

This creates `venv`, installs Python dependencies, checks `ffmpeg`, downloads the default model, and runs `swift build`.

## Build A Local Mac App

```bash
scripts/build_app.sh
```

The app is created at:

```text
dist/Verbatim.app
```

This build is suitable for local testing and early trusted testers. Wider sharing should use a signed and notarized build with a standalone helper executable.

## Permissions

Verbatim needs:

- Microphone access for recording.
- Accessibility access for pasting text into the active app.

Enable Accessibility in:

```text
System Settings > Privacy & Security > Accessibility
```

## Notes

The Git repository does not include:

- `.build`
- `venv`
- downloaded models

Those are generated locally.
