import Foundation
import Combine
import SwiftUI
import AppKit

public enum DictationMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case defaultMode = "Default"
    case code = "Code"
    case email = "Email"
    case messaging = "Messaging"
    case notes = "Notes"
    case blazingFast = "Blazing Fast"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .auto: return "sparkles"
        case .defaultMode: return "waveform"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .email: return "envelope.fill"
        case .messaging: return "message.fill"
        case .notes: return "note.text"
        case .blazingFast: return "bolt.fill"
        }
    }
    
    public var shortcutNumber: Int {
        switch self {
        case .auto: return 0
        case .defaultMode: return 1
        case .code: return 2
        case .email: return 3
        case .messaging: return 4
        case .notes: return 5
        case .blazingFast: return 6
        }
    }
    
    public var description: String {
        switch self {
        case .auto: return "Auto-detects Code, Email, Messaging, or Notes based on front app"
        case .defaultMode: return "Smart grammar, natural flow & punctuation"
        case .code: return "Preserves camelCase, snake_case & code syntax"
        case .email: return "Courteous tone, paragraph line breaks & sign-offs"
        case .messaging: return "Casual tone, spoken emoji translation & slang"
        case .notes: return "Clean markdown notes with minimal clutter"
        case .blazingFast: return "Instant raw transcription (<100ms RTF)"
        }
    }
}

public class ModeManager: ObservableObject {
    public static let shared = ModeManager()
    
    @Published public var currentMode: DictationMode = .auto
    @Published public var effectiveMode: DictationMode = .defaultMode
    @Published public var detectedAppName: String = ""
    @Published public var isPickerVisible: Bool = false
    
    private let modeDefaultsKey = "com.verbatim.dictationMode"
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: modeDefaultsKey),
           let mode = DictationMode(rawValue: saved) {
            self.currentMode = mode
        } else {
            self.currentMode = .auto
        }
    }
    
    public func selectMode(_ mode: DictationMode) {
        self.currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: modeDefaultsKey)
        print("🎯 [ModeManager] Switched dictation mode preference to: \(mode.rawValue)")
    }
    
    public func selectByNumber(_ number: Int) -> Bool {
        if let match = DictationMode.allCases.first(where: { $0.shortcutNumber == number }) {
            selectMode(match)
            return true
        }
        return false
    }
    
    /// Resolves the actual formatting mode to use given the frontmost application
    public func updateEffectiveMode(for app: NSRunningApplication?) {
        let appName = app?.localizedName ?? "Desktop"
        self.detectedAppName = appName
        
        guard currentMode == .auto else {
            self.effectiveMode = currentMode
            return
        }
        
        guard let bundleID = app?.bundleIdentifier?.lowercased() else {
            self.effectiveMode = .defaultMode
            return
        }
        
        // 1. Coding Environments
        if bundleID.contains("vscode") ||
            bundleID.contains("cursor") ||
            bundleID.contains("xcode") ||
            bundleID.contains("terminal") ||
            bundleID.contains("iterm") ||
            bundleID.contains("warp") ||
            bundleID.contains("ghostty") ||
            bundleID.contains("wezterm") ||
            bundleID.contains("sublime") ||
            bundleID.contains("jetbrains") ||
            bundleID.contains("nova") {
            self.effectiveMode = .code
            print("🧠 [ModeManager] Auto-selected Code Mode for \(appName)")
            return
        }
        
        // 2. Messaging & Chat
        if bundleID.contains("slack") ||
            bundleID.contains("discord") ||
            bundleID.contains("mobilesms") ||
            bundleID.contains("telegram") ||
            bundleID.contains("whatsapp") ||
            bundleID.contains("signal") {
            self.effectiveMode = .messaging
            print("🧠 [ModeManager] Auto-selected Messaging Mode for \(appName)")
            return
        }
        
        // 3. Email Clients
        if bundleID.contains("mail") ||
            bundleID.contains("outlook") ||
            bundleID.contains("superhuman") ||
            bundleID.contains("mimestream") {
            self.effectiveMode = .email
            print("🧠 [ModeManager] Auto-selected Email Mode for \(appName)")
            return
        }
        
        // 4. Notes & Documentation
        if bundleID.contains("notion") ||
            bundleID.contains("obsidian") ||
            bundleID.contains("notes") ||
            bundleID.contains("bear") ||
            bundleID.contains("craft") {
            self.effectiveMode = .notes
            print("🧠 [ModeManager] Auto-selected Notes Mode for \(appName)")
            return
        }
        
        self.effectiveMode = .defaultMode
    }
    
    public func togglePicker() {
        self.isPickerVisible.toggle()
    }
    
    public func hidePicker() {
        self.isPickerVisible = false
    }
}
