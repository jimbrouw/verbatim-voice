import Foundation
import Combine
import SwiftUI

public enum DictationMode: String, CaseIterable, Identifiable {
    case defaultMode = "Default"
    case code = "Code"
    case email = "Email"
    case messaging = "Messaging"
    case blazingFast = "Blazing Fast"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .defaultMode: return "waveform"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .email: return "envelope.fill"
        case .messaging: return "message.fill"
        case .blazingFast: return "bolt.fill"
        }
    }
    
    public var shortcutNumber: Int {
        switch self {
        case .defaultMode: return 1
        case .code: return 2
        case .email: return 3
        case .messaging: return 4
        case .blazingFast: return 5
        }
    }
    
    public var description: String {
        switch self {
        case .defaultMode: return "Smart grammar, natural flow & punctuation"
        case .code: return "Preserves camelCase, snake_case & code syntax"
        case .email: return "Courteous tone, paragraph line breaks & sign-offs"
        case .messaging: return "Casual tone, spoken emoji translation & slang"
        case .blazingFast: return "Instant raw transcription (<100ms RTF)"
        }
    }
}

public class ModeManager: ObservableObject {
    public static let shared = ModeManager()
    
    @Published public var currentMode: DictationMode = .defaultMode
    @Published public var isPickerVisible: Bool = false
    
    private let modeDefaultsKey = "com.verbatim.dictationMode"
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: modeDefaultsKey),
           let mode = DictationMode(rawValue: saved) {
            self.currentMode = mode
        }
    }
    
    public func selectMode(_ mode: DictationMode) {
        self.currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: modeDefaultsKey)
        print("🎯 [ModeManager] Switched dictation mode to: \(mode.rawValue)")
    }
    
    public func selectByNumber(_ number: Int) -> Bool {
        if let match = DictationMode.allCases.first(where: { $0.shortcutNumber == number }) {
            selectMode(match)
            return true
        }
        return false
    }
    
    public func togglePicker() {
        self.isPickerVisible.toggle()
    }
    
    public func hidePicker() {
        self.isPickerVisible = false
    }
}
