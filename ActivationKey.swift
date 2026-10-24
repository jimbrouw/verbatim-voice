import AppKit

enum ActivationKey: String, CaseIterable, Identifiable {
    case function
    case option
    case control

    static let defaultsKey = "activationKey"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option:
            return "Option"
        case .function:
            return "Fn"
        case .control:
            return "Control"
        }
    }

    var instructionText: String {
        switch self {
        case .option:
            return "Right Option: hold to talk, tap for hands-free toggle"
        case .function:
            return "Fn (Globe): hold to talk, tap for hands-free toggle"
        case .control:
            return "Control: hold to talk, tap for hands-free toggle"
        }
    }

    static var current: ActivationKey {
        get {
            let rawValue = UserDefaults.standard.string(forKey: defaultsKey) ?? ActivationKey.function.rawValue
            return ActivationKey(rawValue: rawValue) ?? .function
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    func isPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .option:
            return flags.contains(.option)
        case .function:
            return flags.contains(.function)
        case .control:
            return flags.contains(.control)
        }
    }

    func matches(keyCode: CGKeyCode) -> Bool {
        switch self {
        case .option:
            return keyCode == 58 || keyCode == 61 // 58: Left Option, 61: Right Option
        case .function:
            return keyCode == 63 // 63: Fn / Globe key
        case .control:
            return keyCode == 59 || keyCode == 62 // 59: Left Control, 62: Right Control
        }
    }
}
