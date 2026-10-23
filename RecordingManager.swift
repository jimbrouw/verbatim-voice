import Foundation
import Combine
import AppKit

class RecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isHandsFreeMode = false
    @Published var lastTranscription = ""
    @Published var streamingText = ""
    
    let audioManager = AudioManager()
    let transcriber = FluidTranscriber.shared
    private var lastRecordingURL: URL?
    private var recordingStartTime: Date?
    private var pendingStartWorkItem: DispatchWorkItem?
    private var capturedFocusedElement: AXUIElement?
    private var targetApplication: NSRunningApplication?
    
    private let minimumRecordingDuration: TimeInterval = 0.4 // seconds
    
    func startRecording() {
        // Don't start a new recording while processing
        guard !isProcessing else {
            print("⚠️ Skipping - still processing previous recording")
            return
        }
        
        // 1. Pause media playback (Spotify / Music / VLC)
        MediaManager.shared.pausePlaybackIfNeeded()
        
        // 2. Play sound
        SoundManager.shared.playStartSound()
        
        // Capture frontmost application and focused element where cursor currently is
        var front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            front = NSWorkspace.shared.runningApplications.first(where: {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            })
        }
        self.targetApplication = front
        self.capturedFocusedElement = AccessibilityContext.shared.getFocusedElement()
        
        // Capture active on-screen technical keywords for context bias
        ScreenContext.shared.captureFocusedWindowKeywords(for: front?.processIdentifier)
        
        // Start audio capture
        pendingStartWorkItem?.cancel()
        do {
            self.lastRecordingURL = try self.audioManager.startRecording()
            self.recordingStartTime = Date()
            self.streamingText = ""
            self.isRecording = true
            print("🎙️ Started native recording session")
        } catch {
            print("❌ Failed to start recording: \(error)")
        }
    }
    
    func startHandsFreeRecording() {
        guard !isProcessing else { return }
        isHandsFreeMode = true
        print("🎙️ Hands-free recording mode active")
        if !isRecording {
            startRecording()
        }
    }
    
    func stopHandsFreeRecording() {
        guard isHandsFreeMode else { return }
        print("🛑 Hands-free recording stopped")
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
        print("🚫 Recording cancelled")
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
                print("⚠️ Recording too short (\(String(format: "%.2f", duration))s) — discarding silently")
                return
            }
        }
        
        // Guard against instanceBusy
        guard !isProcessing else {
            print("⚠️ Skipping transcription - already processing a previous recording")
            return
        }
        
        SoundManager.shared.playStopSound()
        
        // Check file exists and has content
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard fileSize > 1000 else {
            print("⚠️ Recording file too small (\(fileSize) bytes) — skipping")
            return
        }
        
        print("Stopped recording. File size: \(fileSize) bytes. Starting in-process CoreML ASR...")
        isProcessing = true
        
        transcriber.transcribe(audioURL: url) { [weak self] text in
            guard let self = self else { return }
            
            guard let rawText = text, !rawText.isEmpty else {
                print("⚠️ Empty or nil transcription result")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.streamingText = ""
                }
                return
            }
            
            self.lastTranscription = rawText
            print("✅ Final Transcription: \(rawText)")
            SoundManager.shared.playSuccessSound()
            
            // Format text with context
            let context = AccessibilityContext.shared.getContext()
            let formatted = TextFormatter.shared.format(rawText: rawText, context: context)
            
            // Stream word-by-word into BOTH the active text box and the floating pill UI!
            self.streamWordByWord(formattedText: formatted.text, shouldPressEnter: formatted.shouldPressEnter)
        }
    }
    
    private func streamWordByWord(formattedText: String, shouldPressEnter: Bool) {
        let tokens = TextInjector.shared.tokenizeIntoWords(text: formattedText)
        guard !tokens.isEmpty else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }
        
        let targetApp = self.targetApplication
        self.targetApplication = nil
        let targetElement = self.capturedFocusedElement ?? AccessibilityContext.shared.getFocusedElement()
        self.capturedFocusedElement = nil
        
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
            let useAX = targetElement != nil && TextInjector.shared.canUseAXInjection(on: targetElement!)
            
            for (index, token) in tokens.enumerated() {
                accumulatedText.append(token)
                let currentSnapshot = accumulatedText
                
                // 1. Update UI pill in real time
                DispatchQueue.main.async {
                    self.streamingText = currentSnapshot
                }
                
                // 2. Type word directly into active text box at caret
                if useAX, let element = targetElement, TextInjector.shared.injectTokenDirectly(token, to: element) {
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
