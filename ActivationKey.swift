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
}
