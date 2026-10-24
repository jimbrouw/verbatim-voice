import SwiftUI

public struct ModePickerView: View {
    @ObservedObject var modeManager = ModeManager.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(DictationMode.allCases) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        modeManager.selectMode(mode)
                        modeManager.hidePicker()
                    }
                }) {
                    HStack(spacing: 5) {
                        Text("\(mode.shortcutNumber)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(modeManager.currentMode == mode ? .black : .white.opacity(0.45))
                            .frame(width: 14, height: 14)
                            .background(
                                Circle()
                                    .fill(modeManager.currentMode == mode ? Color(red: 0.28, green: 0.65, blue: 1.0) : Color.white.opacity(0.12))
                            )
                        
                        Image(systemName: mode.iconName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(modeManager.currentMode == mode ? Color(red: 0.35, green: 0.85, blue: 1.0) : .white.opacity(0.75))
                        
                        Text(mode.rawValue)
                            .font(.system(size: 11.5, weight: modeManager.currentMode == mode ? .bold : .medium, design: .rounded))
                            .foregroundColor(modeManager.currentMode == mode ? .white : .white.opacity(0.75))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(modeManager.currentMode == mode ? Color.white.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(red: 0.07, green: 0.08, blue: 0.12).opacity(0.96))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
    }
}
