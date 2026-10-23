import AppKit
import AudioToolbox

class SoundManager {
    static let shared = SoundManager()
    
    private let tinkSound = NSSound(named: "Tink")
    private let popSound = NSSound(named: "Pop")
    private let purrSound = NSSound(named: "Purr")
    
    /// Use system sound for "start recording" - soft, instantaneous click
    func playStartSound() {
        if let sound = tinkSound {
            sound.stop()
            sound.play()
        } else {
            AudioServicesPlaySystemSound(1057)
        }
    }
    
    /// Use system sound for "stop recording" - soft pop
    func playStopSound() {
        if let sound = popSound {
            sound.stop()
            sound.play()
        } else {
            AudioServicesPlaySystemSound(1104)
        }
    }
    
    /// Soft feedback chime on successful transcription
    func playSuccessSound() {
        if let sound = purrSound {
            sound.stop()
            sound.play()
        } else {
            AudioServicesPlaySystemSound(1054)
        }
    }
}
