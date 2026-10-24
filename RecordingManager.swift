import Foundation
import Combine
import AppKit

class RecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isHandsFreeMode = false
    @Published var lastTranscription = ""
    @Published var streamingText = ""
    
    let audioManager = AudioManager.shared
    let transcriber = FluidTranscriber.shared
    private var lastRecordingURL: URL?
    private var recordingStartTime: Date?
    private var pendingStartWorkItem: DispatchWorkItem?
    private var capturedFocusedElement: AXUIElement?
    private var targetApplication: NSRunningApplication?
    
    private let minimumRecordingDuration: TimeInterval = 0.35 // seconds
    
    func startRecording() {
        // Don't start a new recording while processing previous dictation
        guard !isProcessing else {
            print("⚠️ [RecordingManager] Skipping start - still processing previous recording")
            return
        }
        
        // 1. Pause media playback (Spotify / Music / VLC)
        MediaManager.shared.pausePlaybackIfNeeded()
        
        // 2. Play soft click start sound
        SoundManager.shared.playStartSound()
        
        // 3. Capture frontmost application and focused element where cursor currently is
        var front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            front = NSWorkspace.shared.runningApplications.first(where: {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            })
        }
        self.targetApplication = front
        self.capturedFocusedElement = AccessibilityContext.shared.getFocusedElement()
        
        // Update context mode based on frontmost application
        ModeManager.shared.updateEffectiveMode(for: front)
        
        // 4. Capture active on-screen technical keywords for context bias
        ScreenContext.shared.captureFocusedWindowKeywords(for: front?.processIdentifier)
        
        // 5. Start native CoreAudio capture
        pendingStartWorkItem?.cancel()
        do {
            self.lastRecordingURL = try self.audioManager.startRecording()
            self.recordingStartTime = Date()
            self.streamingText = ""
            self.isRecording = true
            print("🎙️ [RecordingManager] Started native recording session for app: \(front?.localizedName ?? "unknown")")
        } catch {
            print("❌ [RecordingManager] Failed to start recording: \(error)")
        }
    }
    
    func startHandsFreeRecording() {
        guard !isProcessing else { return }
        isHandsFreeMode = true
        print("🎙️ [RecordingManager] Hands-free recording mode active")
        if !isRecording {
            startRecording()
        }
    }
    
    func stopHandsFreeRecording() {
        guard isHandsFreeMode else { return }
        print("🛑 [RecordingManager] Hands-free recording stopped")
        stopRecording()
    }
    
    /// Silently discards accidental key taps (<0.4s) with zero sound, zero errors, and zero transcription
    func silentDiscard() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        if isRecording {
            audioManager.stopRecording()
            audioManager.currentAmplitude = 0.0
            isRecording = false
        }
        isHandsFreeMode = false
        streamingText = ""
        MediaManager.shared.resumePlaybackIfNeeded()
        print("🔇 [RecordingManager] Recording silently discarded (<0.4s tap)")
    }
    
    func cancelRecording() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        if isRecording {
            audioManager.stopRecording()
            audioManager.currentAmplitude = 0.0
            isRecording = false
        }
        isHandsFreeMode = false
        streamingText = ""
        MediaManager.shared.resumePlaybackIfNeeded()
        print("🚫 [RecordingManager] Recording cancelled")
    }
    
    func stopRecording() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        
        guard isRecording else {
            isHandsFreeMode = false
            MediaManager.shared.resumePlaybackIfNeeded()
            return
        }
        
        audioManager.stopRecording()
        audioManager.currentAmplitude = 0.0 // Reset waveform
        isRecording = false
        isHandsFreeMode = false
        MediaManager.shared.resumePlaybackIfNeeded()
        
        guard let url = lastRecordingURL else { return }
        
        // Check minimum recording duration to avoid zero-length files
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            if duration < minimumRecordingDuration {
                print("⚠️ [RecordingManager] Recording too short (\(String(format: "%.2f", duration))s) — discarding silently")
                return
            }
        }
        
        // Guard against instanceBusy
        guard !isProcessing else {
            print("⚠️ [RecordingManager] Skipping transcription - already processing a previous recording")
            return
        }
        
        SoundManager.shared.playStopSound()
        
        // Check file exists and has content
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard fileSize > 1000 else {
            print("⚠️ [RecordingManager] Recording file too small (\(fileSize) bytes) — skipping")
            return
        }
        
        print("🛑 [RecordingManager] Stopped recording. File size: \(fileSize) bytes. Starting in-process CoreML ASR...")
        isProcessing = true
        
        transcriber.transcribe(audioURL: url) { [weak self] text in
            guard let self = self else { return }
            
            guard let rawText = text, !rawText.isEmpty else {
                print("⚠️ [RecordingManager] Empty or nil transcription result")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.streamingText = ""
                }
                return
            }
            
            self.lastTranscription = rawText
            print("✅ [RecordingManager] Final Transcription: \"\(rawText)\"")
            SoundManager.shared.playSuccessSound()
            
            // Format text with context (SmartBacktracker, homophones, screen context, capitalization)
            let context = AccessibilityContext.shared.getContext()
            let formatted = TextFormatter.shared.format(rawText: rawText, context: context)
            
            // Inject text into the user's cursor position and update UI
            self.injectFormattedText(formatted.text, shouldPressEnter: formatted.shouldPressEnter)
        }
    }
    
    private func injectFormattedText(_ formattedText: String, shouldPressEnter: Bool) {
        let tokens = TextInjector.shared.tokenizeIntoWords(text: formattedText)
        guard !tokens.isEmpty else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.streamingText = ""
            }
            return
        }
        
        let targetApp = self.targetApplication
        self.targetApplication = nil
        let targetElement = self.capturedFocusedElement ?? AccessibilityContext.shared.getFocusedElement()
        self.capturedFocusedElement = nil
        
        // Log to local dictation history
        HistoryManager.shared.record(text: formattedText, app: targetApp, mode: ModeManager.shared.effectiveMode.rawValue)
        
        let pasteboard = NSPasteboard.general
        let savedItems = TextInjector.shared.backupPasteboard(pasteboard)
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            // Re-activate target app if it lost focus
            if let app = targetApp, !app.isActive {
                DispatchQueue.main.async {
                    app.activate()
                }
                usleep(40_000)
            }
            
            var accumulatedText = ""
            var useAX = AXIsProcessTrusted() && targetElement != nil && TextInjector.shared.canUseAXInjection(on: targetElement!)
            print("⌨️ [RecordingManager] Injecting \(tokens.count) tokens into \(targetApp?.localizedName ?? "unknown") (trusted: \(AXIsProcessTrusted()), AX settable: \(useAX))")
            
            for (index, token) in tokens.enumerated() {
                accumulatedText.append(token)
                let currentSnapshot = accumulatedText
                
                // 1. Update UI pill in real time
                DispatchQueue.main.async {
                    self.streamingText = currentSnapshot
                }
                
                // 2. Type word directly into active text box at caret
                if index == 0, useAX, let element = targetElement {
                    // Verify the first word really landed; some apps (Electron) fake AX success
                    if TextInjector.shared.injectTokenDirectlyVerified(token, to: element) {
                        print("✅ [RecordingManager] AX insertion verified — streaming via Accessibility")
                    } else {
                        print("📋 [RecordingManager] AX insertion not effective — switching to Cmd+V paste")
                        useAX = false
                        TextInjector.shared.injectTokenViaPasteboard(token)
                    }
                } else if useAX, let element = targetElement, TextInjector.shared.injectTokenDirectly(token, to: element) {
                    // Direct AX insertion succeeded
                } else {
                    // Rock-solid token-by-token Cmd+V paste with hardware modifier sequence
                    TextInjector.shared.injectTokenViaPasteboard(token)
                }
                
                // 65ms natural typewriter cadence between words
                if index < tokens.count - 1 {
                    usleep(65_000)
                }
            }
            
            // Handle spoken command "press enter"
            if shouldPressEnter {
                usleep(80_000)
                DispatchQueue.main.async {
                    TextInjector.shared.postReturnKey()
                }
            }
            
            // Restore user's previous clipboard after streaming completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                TextInjector.shared.restorePasteboard(savedItems, to: pasteboard)
            }
            
            // Keep final text visible in pill for 1.4s so user can read it
            usleep(1_400_000)
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isHandsFreeMode = false
                self.streamingText = ""
            }
        }
    }
}
