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
        guard !formattedText.isEmpty else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.streamingText = ""
            }
            return
        }
        
        // Show dictated result immediately in floating pill HUD
        DispatchQueue.main.async {
            self.streamingText = formattedText
        }
        
        let targetApp = self.targetApplication
        self.targetApplication = nil
        let targetElement = self.capturedFocusedElement ?? AccessibilityContext.shared.getFocusedElement()
        self.capturedFocusedElement = nil
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            // Ensure target application is active before typing/pasting
            if let app = targetApp, !app.isActive {
                DispatchQueue.main.async {
                    app.activate()
                }
                usleep(50_000) // 50ms for window server focus switch
            }
            
            // Inject complete text at cursor position (AX direct or transient zero-pollution pasteboard)
            TextInjector.shared.inject(text: formattedText, targetElement: targetElement)
            
            // Handle spoken command "press enter"
            if shouldPressEnter {
                usleep(80_000)
                DispatchQueue.main.async {
                    TextInjector.shared.postReturnKey()
                }
            }
            
            // Keep final text visible in pill for 1.4s so user can read what was dictated
            usleep(1_400_000)
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isHandsFreeMode = false
                self.streamingText = ""
            }
        }
    }
}
