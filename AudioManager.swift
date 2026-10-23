import Foundation
import AVFoundation

class AudioManager: NSObject, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    @Published var permissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var currentAmplitude: Float = 0.0
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if permissionStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.permissionStatus = granted ? .authorized : .denied
                }
            }
        }
    }
    
    func startRecording() throws -> URL {
        // Clean up previous engine state safely
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        
        print("🎤 Mic native format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch")
        guard nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0 else {
            throw NSError(
                domain: "com.verbatim.audio",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid microphone format: sample rate or channels is 0"]
            )
        }
        
        // Setup temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording.wav")
        
        // Delete old file if it exists
        try? FileManager.default.removeItem(at: fileURL)
        self.recordingURL = fileURL
        
        // Record in the mic's native format
        audioFile = try AVAudioFile(forWriting: fileURL, settings: nativeFormat.settings)
        
        // Install tap with 4096 buffer size
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] (buffer, time) in
            guard let self = self, let audioFile = self.audioFile else { return }
            
            // Compute RMS amplitude for waveform visualization
            if let channelData = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(max(count, 1)))
                DispatchQueue.main.async {
                    self.currentAmplitude = rms
                }
            }
            
            // Write raw native audio to file
            try? audioFile.write(from: buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        return fileURL
    }
    
    func stopRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()
        audioFile = nil // Close the file cleanly
    }
}
