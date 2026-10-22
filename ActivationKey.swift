import AppKit

enum ActivationKey: String, CaseIterable, Identifiable {
    case function
    case option
    case control

    static let defaultsKey = "activationKey"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .function:
            return "Fn"
        case .option:
            return "Option"
        case .control:
            return "Control"
        }
    }

    var instructionText: String {
        "\(displayName): hold to dictate, double-tap for hands-free"
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
        case .function:
            return flags.contains(.function)
        case .option:
            return flags.contains(.option)
        case .control:
            return flags.contains(.control)
        }
    }

    func matches(keyCode: CGKeyCode) -> Bool {
        switch self {
        case .function:
            return keyCode == 63 // 0x3F: Fn / Globe key
        case .option:
            return keyCode == 58 || keyCode == 61 // Left / Right Option
        case .control:
            return keyCode == 59 || keyCode == 62 // Left / Right Control
        }
    }
}
