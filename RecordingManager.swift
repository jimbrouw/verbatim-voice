import Foundation
import Combine

class RecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isHandsFreeMode = false
    @Published var lastTranscription = ""
    @Published var streamingText = ""
    
    let audioManager = AudioManager()
    let mlxTranscriber = MLXTranscriber()
    private var lastRecordingURL: URL?
    private var recordingStartTime: Date?
    private var pendingStartWorkItem: DispatchWorkItem?
    
    private let minimumRecordingDuration: TimeInterval = 0.5 // seconds
    
    func startRecording() {
        // Don't start a new recording while processing
        guard !isProcessing else {
            print("⚠️ Skipping - still processing previous recording")
            return
        }
        
        // 1. Play sound first
        SoundManager.shared.playStartSound()
        
        // 2. Wait 300ms for beep to finish before starting mic tap
        pendingStartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingStartWorkItem = nil
            guard !self.isRecording, !self.isProcessing else { return }
            
            do {
                self.lastRecordingURL = try self.audioManager.startRecording()
                self.recordingStartTime = Date()
                self.streamingText = ""
                self.isRecording = true
                print("🎙️ Started recording (post-beep)")
            } catch {
                print("❌ Failed to start recording: \(error)")
            }
        }
        pendingStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    func startHandsFreeRecording() {
        guard !isRecording, !isProcessing else { return }
        isHandsFreeMode = true
        print("🎙️ Hands-free recording started")
        startRecording()
    }
    
    func stopHandsFreeRecording() {
        guard isHandsFreeMode else { return }
        print("🛑 Hands-free recording stopped")
        stopRecording()
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
        print("🚫 Recording cancelled")
    }
    
    func stopRecording() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        
        guard isRecording else {
            isHandsFreeMode = false
            return
        }
        
        audioManager.stopRecording()
        audioManager.currentAmplitude = 0.0 // Reset waveform
        isRecording = false
        isHandsFreeMode = false
        SoundManager.shared.playStopSound()
        
        guard let url = lastRecordingURL else { return }
        
        // Check minimum recording duration to avoid zero-length files
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            if duration < minimumRecordingDuration {
                print("⚠️ Recording too short (\(String(format: "%.2f", duration))s) — skipping transcription")
                return
            }
        }
        
        // Guard against instanceBusy
        guard !isProcessing else {
            print("⚠️ Skipping transcription - already processing a previous recording")
            return
        }
        
        // Check file exists and has content
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard fileSize > 1000 else {
            print("⚠️ Recording file too small (\(fileSize) bytes) — skipping")
            return
        }
        
        print("Stopped recording. File size: \(fileSize) bytes. Starting local transcription...")
        isProcessing = true
        
        mlxTranscriber.transcribe(audioURL: url) { [weak self] text in
            guard let self = self else { return }
            
            self.isProcessing = false
            if let text = text, !text.isEmpty {
                self.lastTranscription = text
                print("✅ Final Transcription: \(text)")
                SoundManager.shared.playSuccessSound()
                
                // Inject text into active app
                TextInjector.shared.inject(text: text)
            } else {
                print("⚠️ Empty or nil transcription result")
            }
        }
    }
}
