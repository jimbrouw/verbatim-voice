import AVFoundation
import AppKit

class SoundManager {
    static let shared = SoundManager()
    
    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    
    func playStartSound() {
        // Use system sound for "start recording" - a soft, low pop
        playTone(frequency: 880, duration: 0.08, volume: 0.4)
    }
    
    func playStopSound() {
        // Use system sound for "stop recording" - slightly lower tone
        playTone(frequency: 660, duration: 0.1, volume: 0.3)
    }
    
    func playSuccessSound() {
        // Soft chime on successful transcription
        playTone(frequency: 1047, duration: 0.12, volume: 0.25)
    }
    
    private func playTone(frequency: Double, duration: Double, volume: Float) {
        let sampleRate = 44100.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        let channelData = buffer.floatChannelData![0]
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Sine wave with a quick fade-out envelope for a "click" feel
            let envelope = max(0, 1.0 - (t / duration))
            channelData[i] = Float(sin(2.0 * .pi * frequency * t) * envelope * Double(volume))
        }
        
        // Play using AVAudioEngine for zero-latency output
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
            playerNode.play()
            
            // Keep engine alive for the duration of the tone
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                engine.stop()
            }
        } catch {
            // Silently fail - sounds are non-critical
        }
    }
}
