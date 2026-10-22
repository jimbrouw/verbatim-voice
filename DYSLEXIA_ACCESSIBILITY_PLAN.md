# Verbatim: Dyslexia-First Voice & Comprehension Assistant
## Technical Specification & Milestone Roadmap

> **Core Thesis**: For a dyslexic thinker, reading dense technical jargon and organizing complex thoughts into text are the two biggest cognitive bottlenecks. Verbatim transforms macOS from a text-heavy environment into a voice-first, low-friction operating system that summarizes inbound text and structures outbound thoughts—running 100% locally and privately on Apple Silicon.

---

## 1. Feature Prioritization Matrix

| Feature | Primary Problem Solved | Complexity | Latency Budget | Priority |
| :--- | :--- | :--- | :--- | :--- |
| **1. TL;DR & Plain English Translator** | Reading fatigue from AI/tech jargon | Medium | < 500 ms | **Phase 1 (Now)** |
| **2. Spoken Brain-Dump Untangle** | Formulating structured messages from rambling thoughts | Medium | < 600 ms | **Phase 2** |
| **3. Synchronized Word-Highlight Readback** | Losing place when listening to text | Low | Instant (Native) | **Phase 3** |
| **4. Self-Learning Phonetic Dictionary** | Misspelling technical acronyms and names | Low | < 5 ms | **Phase 4** |
| **5. Embedded Kokoro Neural TTS** | Upgrading beyond Apple's system voices | High | < 250 ms | **Deferred** |

---

## 2. Phase 1 Deep-Dive: "TL;DR & Plain English Translator"

### The User Experience (Target Interaction)
1. You are looking at a dense AI response, technical GitHub documentation, or a confusing email.
2. You select the text with your mouse and press a dedicated shortcut: **`Option + Space`** (or double-tap `Option`).
3. Instantly (< 400 ms), a clean, frosted-glass HUD appears next to your cursor with:
   - **One-Sentence TL;DR**: The bottom-line summary in everyday words.
   - **Key Actions / Takeaways**: 2–3 clear bullet points (no fluff or buzzwords).
   - **One-Click Audio Button**: Automatically triggers macOS Speech to read the summary aloud while your eyes take a break.
4. Pressing `Escape` or clicking outside dismisses the HUD immediately.

### Technical Architecture
```
[User Selects Text] ──> [Option + Space] 
                            │
                            ▼
               [Accessibility / Clipboard Capture]
               (Grabs selected string without losing clipboard)
                            │
                            ▼
                 [Local MLX LLM Engine]
               (Llama-3.2-1B-Instruct / Qwen-2.5-1.5B)
               Prompt: "Translate to Plain English for Dyslexia"
                            │
                            ▼
              [SwiftUI Floating Summary Card]
              ├── TL;DR Sentence (High legibility, bold highlights)
              ├── Action Bullets
              └── [🔊 Read Aloud] (Invokes AVSpeechSynthesizer)
```

### Prompt Engineering for Dyslexic Comprehension
The prompt is specifically tuned to eliminate cognitive overload:
```text
You are a cognitive translation assistant for a dyslexic thinker.
Your job is to strip out academic jargon, tech buzzwords, and fluff, and explain the core point in direct, punchy, plain English.

Input Text:
"""
{selected_text}
"""

Format your response exactly like this:
TL;DR: [1 clear sentence explaining what this actually means in real life]

KEY POINTS:
• [Action or fact 1]
• [Action or fact 2]
• [Action or fact 3 if applicable]
```

---

## 3. Phase 2: "Spoken Brain-Dump Untangle"

### The User Experience
1. Instead of agonizing over how to draft an email or reply:
2. Hold **`Option + Shift`** and speak your raw stream of consciousness:
   > *"Tell Sarah I went through the slides, the design on slide 4 is messy and needs bigger numbers, but slide 6 is great, and ask if we're still presenting at 2 PM tomorrow or if it got moved."*
3. Release the keys.
4. In under **600 ms**, Verbatim cleans up the structure and pastes:
   > *"Hi Sarah, I reviewed the slides. Slide 6 looks great! On slide 4, the layout feels a bit crowded—could we make the numbers larger? Also, could you confirm if our presentation is still scheduled for 2:00 PM tomorrow? Thanks!"*

---

## 4. Phase 3: Synchronized Word-Highlight Readback

### Why This Matters for Dyslexia
When the Mac voice speaks text aloud, dyslexic readers often lose track of which word is being spoken. Synchronized audio-visual highlighting ("karaoke-style" tracking) increases comprehension speed by over 40% because your eyes and ears work together.

### Native Implementation via Apple APIs
macOS provides this out of the box in `AVSpeechSynthesizerDelegate`:
```swift
func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    willSpeakRangeOfSpeechString characterRange: NSRange,
    utterance: AVSpeechUtterance
) {
    // Update the active highlighted range in your SwiftUI view
    DispatchQueue.main.async {
        self.highlightedRange = characterRange
    }
}
```

---

## 5. Implementation Roadmap: What to Build First

### Sprint 1 (Next Step): Build the TL;DR Pipeline
- [ ] **Step 1**: In `mlx_server.py`, add a `/summarize` endpoint loading `mlx-community/Llama-3.2-1B-Instruct-4bit` (consumes only ~800MB RAM, runs at 90 tokens/sec on Apple Silicon).
- [ ] **Step 2**: Create `SelectedTextReader.swift` using macOS Accessibility (`AXUIElementCopyAttributeValue` for `kAXSelectedTextAttribute`) with a fallback to `Cmd + C` clipboard capture.
- [ ] **Step 3**: Create `SummaryCardView.swift` — a minimal, non-intrusive floating window that renders the TL;DR and bullets.
- [ ] **Step 4**: Wire the shortcut `Option + Space` in `HotkeyManager.swift` to trigger the flow.

### Sprint 2: Untangle Mode (Outbound Voice)
- [ ] **Step 5**: Add `/untangle` prompt to `mlx_server.py`.
- [ ] **Step 6**: Add dual-mode modifier detection in `HotkeyManager.swift` (`Option` = Literal Dictation, `Option + Shift` = Untangle).

### Sprint 3: Audio-Visual Sync & Dictionary
- [ ] **Step 7**: Add `AVSpeechSynthesizerDelegate` to highlight words in real time inside the Summary Card.
- [ ] **Step 8**: Add `dictionary.json` phonetic replacement table.
