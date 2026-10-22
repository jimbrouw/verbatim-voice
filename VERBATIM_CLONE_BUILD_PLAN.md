# Verbatim Voice (Wispr Flow Clone) — Architecture & Build Plan

> **Goal**: Build a private, 100% offline macOS dictation app matching the speed, ergonomics, and intelligence of Wispr Flow, running natively on Apple Silicon without cloud dependencies or subscription costs.

---

## 1. System Architecture & Comparison

```
┌────────────────────────────────────────────────────────────────────────┐
│                        WISPR FLOW (REVERSE ENGINEERED)                 │
│                                                                        │
│  [Electron Main] <──fd3 JSON──> [Swift Helper]                         │
│         │                             │                                │
│         ▼                             ▼                                │
│  [Hidden WebAudio Worklet]     [CGEventTap & AXUIElement]              │
│         │                             │                                │
│         ▼ gRPC / WS                   │                                │
│  [Cloud: Baseten ASR + OpenPipe LLaMA-3.1-8B + Claude Haiku]           │
│         │                                                              │
│         ▼                                                              │
│  [Clipboard Paste + Cmd+V]                                             │
└────────────────────────────────────────────────────────────────────────┘

                                   VS

┌────────────────────────────────────────────────────────────────────────┐
│                   VERBATIM (LOCAL-ONLY CLONE DESIGN)                   │
│                                                                        │
│  [Swift Native macOS App]                                              │
│  ├── HotkeyManager (CGEvent.tapCreate: Fn / Option hold & double-tap)  │
│  ├── AccessibilityContext (AXUIElement: caret, beforeText, app info)   │
│  ├── AudioManager (AVAudioEngine: 16kHz Float32 buffer)                │
│  ├── FloatingPillWindow (SwiftUI HUD: real-time waveform & live words) │
│  └── TextInjector (Clipboard save + write + Cmd+V + restore + Enter)   │
│         │                                                              │
│         ▼ Local Unix Domain Socket / In-Process C-API                  │
│  [Local ML Engine (Apple Silicon / MLX / Whisper.cpp)]                 │
│  ├── Fast ASR: Parakeet TDT 110M / Whisper Large-v3 Turbo (150ms)      │
│  └── Local Formatter: Deterministic Rules + MLX Llama-3.2-1B / Qwen    │
└────────────────────────────────────────────────────────────────────────┘
```

### Why Native Swift Beats Electron For A Local App
- **Memory footprint**: ~40 MB RAM (Swift) vs. 350–500 MB (Wispr Flow's 7 Electron browser processes + Swift helper).
- **Zero Process IPC Latency**: Eliminates the `stdio[3]` JSON serialization overhead between Electron and Helper.
- **Instant Activation**: Audio recording begins under **15 ms** from keypress, rather than traversing IPC and WebAudio renderers.

---

## 2. Answering Key Technical Questions

### A. Live Word-by-Word Preview ("Ghost Text")
**How Wispr Flow does it**:
- Wispr Flow streams 40 ms audio chunks over gRPC/WebSocket to its server.
- The server emits partial tokens which update the **floating overlay bar** (`dictation:setStreamingTextState`).
- **Crucial finding**: Wispr Flow **does NOT type word-by-word into the target application directly**. Typing character-by-character into third-party apps creates severe issues: it pollutes the target app's undo stack (`Cmd+Z`), triggers external auto-complete popups, loses keystrokes during lag, and prevents retroactive grammar correction.
- **Wispr Flow's approach**: Live words stream into the **floating pill HUD**, and upon key release, the fully polished text is pasted atomically via `Clipboard + Cmd+V` in **~30 ms**.

**How to implement it locally in Verbatim**:
1. Run continuous streaming ASR (using sliding 400 ms windows with Parakeet or Whisper streaming).
2. Publish partial transcript updates to `FloatingPillView` via `@Published var liveTranscript: String`.
3. The floating pill expands smoothly to show real-time transcription as you speak.
4. On key release, the final text passes through the formatter and is injected via `TextInjector.inject(text:)`.

---

### B. Backtracking & Mistake Handling ("No, not that, stop")
**What the reverse-engineered code revealed**:
- Wispr Flow has a dedicated feature called **Smart Formatting Backtrack** (`SmartFormattingBacktrack`).
- Example from Wispr Flow's onboarding:
  > *"Flow can auto correct mistakes: 'How's 6, no 7?' → 'How's 7?'"*
- In `index.js` (`@3467403`), the client checks:
  ```javascript
  const isBacktrack = (rawAsr, formatted) => {
    const rawWords = rawAsr.split(" ");
    const formattedWords = formatted.split(" ");
    const shortened = rawWords.length - formattedWords.length > 3;
    const hasTriggers = ["actually", "scratch that", "no"].some(t =>
      new RegExp(`\\b${t}\\b`, "i").test(rawAsr)
    );
    return shortened && hasTriggers;
  };
  ```

**How to replicate it locally**:
1. **Fast-path deterministic rule engine** (zero latency):
   - **"scratch that" / "delete that"**: Drops the phrase preceding the command.
   - **"no, [X]" / "wait, [X]"**: Drops the immediate prior clause.
2. **Local LLM Cleanup Pass (Optional / Recommended)**:
   - Pipe raw ASR text through an ultra-fast quantized model (e.g., `mlx-community/Llama-3.2-1B-Instruct-4bit` or `Qwen2.5-1.5B-Instruct-4bit`) with prompt:
     ```text
     You are a spoken-to-written text cleaner. 
     Remove filler words (um, uh). 
     Resolve speech self-corrections (e.g. "Meet me at 5 no wait 6" -> "Meet me at 6"). 
     Do not answer the text, only output the cleaned transcription.
     Input: {raw_text}
     Cleaned:
     ```
   - On Apple Silicon (M1/M2/M3/M4), a 1B model generates 10–20 words in **under 80 ms**.

---

### C. Which AIs Wispr Flow Uses
Static analysis of `.webpack/main/index.js` (`@2729992`, `@3114537`, `@3135211`) revealed the exact cloud stack:
1. **Dictation Formatting**:
   - Primary: **OpenPipe fine-tuned LLaMA 3.1 8B** (`openpipe:llama3-1-8b-12-09-2024` and `openpipe:llama3-1-05-21-data-email`).
2. **Tone Rewrite & "Polish"**:
   - Uses **Anthropic Claude 3.5 Haiku** (`claude-haiku-4-5`), **Claude 3.5 Sonnet** (`claude-sonnet-4-5`), and **Cerebras LLaMA 120B** (`gpt-oss-120b`).
3. **ASR**:
   - Hosted Whisper/Conformer models on **Baseten** (`chain-o232k03l.api.baseten.co`) and OpenAI Whisper (`/llm/asr`).

**Local replacement for Verbatim**:
- **ASR**: `mlx-community/parakeet-tdt_ctc-110m` (fastest, ~100ms) or `whisper-large-v3-turbo` (highest accuracy).
- **Formatter / Backtrack**: Local `Llama-3.2-1B-Instruct` (MLX 4-bit) or deterministic regex rules.

---

## 3. MVP Scope vs Future Roadmap

### MVP Scope (Week 1–2) — "Feels Like Wispr Flow"
- [ ] **Ergonomic Hotkey Engine**:
  - Hold `Fn` (or `Option`) to talk; release to paste.
  - Double-tap within `500 ms` for Hands-Free mode (`POPO`).
  - Single-tap or `Escape` while hands-free stops and commits.
  - Event suppression so macOS doesn't chime on modifier press.
- [ ] **Context-Aware Text Injection**:
  - Read `beforeText` via macOS Accessibility (`AXUIElement`).
  - Prepend leading space if cursor isn't after space/newline.
  - Capitalize first word only if at start of sentence or document.
- [ ] **Voice Command**:
  - Detect `"press enter"` at end of speech $\rightarrow$ strip words $\rightarrow$ paste $\rightarrow$ post `Return` keycode (`0x24`).
- [ ] **Personal Dictionary & Snippets**:
  - Local `dictionary.json` supporting replacements (`phrase` $\rightarrow$ `replacement`) and snippet expansions.
- [ ] **UI Polish**:
  - Floating pill HUD with smooth audio waveform and visual lock indicator.

### Phase 2 Scope (Week 3–4) — "Power Features"
- [ ] **Live Word Streaming**: Real-time partial transcript preview inside the floating pill HUD.
- [ ] **Smart Formatting & Backtrack**: Local 1B LLM cleanup pass for self-corrections ("no, not that...").
- [ ] **Transcript History Window**: Searchable SQLite local database with copy, replay audio, and stats (WPM, words dictated).
- [ ] **App-Specific Profiles**: Detect frontmost app (Slack, Terminal, Mail, Cursor) and adjust formatting rules.

---

## 4. Implementation Steps (Step-by-Step)

### Step 1: Upgrade `HotkeyManager.swift` with CGEventTap
Replace `NSEvent.addGlobalMonitorForEvents` with a lower-level `CGEvent.tapCreate` on HID events:
- Allows capturing the `Fn` (Globe) key reliably (keycode `0x3F` / 63).
- Allows swallowing the event so the OS does not trigger system dictation or special character popups.
- Standardizes the **500 ms double-tap window** matching Wispr Flow's `DICTATION_DEBOUNCE_DELAY`.

### Step 2: Implement Context Auto-Capture in `AccessibilityContext.swift`
Create a helper to read surrounding text before pasting:
```swift
func getSurroundingText() -> (before: String, after: String) {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedApp: AnyObject?
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else { return ("", "") }
    
    var focusedElement: AnyObject?
    guard AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else { return ("", "") }
    
    // Read text value and selection range
    var val: AnyObject?
    AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &val)
    
    var selectedRangeValue: AnyObject?
    AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
    
    // Compute beforeText / afterText around cursor
    ...
}
```

### Step 3: Add `TextFormatter.swift` Pipeline
Run transcript through deterministic pipeline before calling `TextInjector`:
1. Check snippet triggers (exact match of stripped text).
2. Apply personal dictionary regex replacement.
3. Check `"press enter"` suffix $\rightarrow$ set `shouldPressEnter = true`.
4. Check `beforeText`: adjust leading whitespace and capitalization.

### Step 4: Add Real-Time Live Word Streaming to `FloatingPillView.swift`
- In `RecordingManager`, stream audio buffers to `MLXTranscriber` in chunks or run a lightweight streaming worker.
- Bind `transcriber.partialTranscript` to a text view inside the pill that animates as you speak.
- Maintain atomic paste on key release.
