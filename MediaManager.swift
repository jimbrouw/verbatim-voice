import Foundation
import AppKit

public class MediaManager {
    public static let shared = MediaManager()
    
    private let queue = DispatchQueue(label: "com.verbatim.media-manager", qos: .utility)
    
    private var didPauseSpotify: Bool = false
    private var didPauseMusic: Bool = false
    private var didPauseVLC: Bool = false
    
    public init() {}
    
    // MARK: - Pause Playback
    
    public func pausePlaybackIfNeeded() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Spotify
            if self.isAppRunning(bundleIdentifier: "com.spotify.client") {
                let script = """
                tell application "Spotify"
                    if player state is playing then
                        pause
                        return true
                    end if
                    return false
                end tell
                """
                if self.runAppleScript(script) == "true" {
                    self.didPauseSpotify = true
                    print("🎵 [MediaManager] Paused Spotify for voice capture")
                }
            }
            
            // 2. Apple Music
            if self.isAppRunning(bundleIdentifier: "com.apple.Music") {
                let script = """
                tell application "Music"
                    if player state is playing then
                        pause
                        return true
                    end if
                    return false
                end tell
                """
                if self.runAppleScript(script) == "true" {
                    self.didPauseMusic = true
                    print("🎵 [MediaManager] Paused Apple Music for voice capture")
                }
            }
            
            // 3. VLC
            if self.isAppRunning(bundleIdentifier: "org.videolan.vlc") {
                let script = """
                tell application "VLC"
                    if playing then
                        play
                        return true
                    end if
                    return false
                end tell
                """
                if self.runAppleScript(script) == "true" {
                    self.didPauseVLC = true
                    print("🎵 [MediaManager] Paused VLC for voice capture")
                }
            }
        }
    }
    
    // MARK: - Resume Playback
    
    public func resumePlaybackIfNeeded() {
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            
            if self.didPauseSpotify {
                self.didPauseSpotify = false
                let script = "tell application \"Spotify\" to play"
                _ = self.runAppleScript(script)
                print("🎵 [MediaManager] Resumed Spotify")
            }
            
            if self.didPauseMusic {
                self.didPauseMusic = false
                let script = "tell application \"Music\" to play"
                _ = self.runAppleScript(script)
                print("🎵 [MediaManager] Resumed Apple Music")
            }
            
            if self.didPauseVLC {
                self.didPauseVLC = false
                let script = "tell application \"VLC\" to play"
                _ = self.runAppleScript(script)
                print("🎵 [MediaManager] Resumed VLC")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func isAppRunning(bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if errorDict != nil {
            return nil
        }
        return result.stringValue
    }
}
