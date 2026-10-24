import SwiftUI
import Combine

// MARK: - Wispr Flow Voice Interaction Pill v3
// Electric Blue / Cyan theme with emerald Hands-Free Lock indicator,
// floating interactive mode switcher, dynamic sizing, and silky EMA waveform.

struct FloatingPillView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @ObservedObject var modeManager = ModeManager.shared
    
    // Waveform rendering state with silky Exponential Moving Average (EMA)
    @State private var wavePhase: Double = 0
    @State private var displayedAmplitude: Double = 0.25
    @State private var animationTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    
    private let barCount = 12
    
    var body: some View {
        VStack(spacing: 8) {
            // 1. Floating Mode Picker (toggled via Right Shift or click)
            if modeManager.isPickerVisible {
                ModePickerView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // 2. Main Interactive Pill
            HStack(spacing: 0) {
                ZStack {
                    // Dark obsidian frosted glass capsule background
                    Capsule()
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.13).opacity(0.95))
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            accentColor.opacity(0.65),
                                            accentColor.opacity(0.25),
                                            accentColor.opacity(0.55)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: accentColor.opacity(0.35), radius: 14, x: 0, y: 4)
                    
                    HStack(spacing: 10) {
                        // A. Leading State Indicator (Mic, Checkmark, or Lock)
                        Group {
                            if recordingManager.isProcessing {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 1.0))
                                    .shadow(color: Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.8), radius: 6)
                            } else {
                                // Pulsing glowing audio mic
                                ZStack {
                                    Circle()
                                        .fill(accentColor.opacity(0.25))
                                        .frame(width: 22, height: 22)
                                        .scaleEffect(pulseScale)
                                    
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(accentColor)
                                        .shadow(color: accentColor.opacity(0.9), radius: 5)
                                }
                            }
                        }
                        .frame(width: 22, height: 22)
                        
                        // B. Hands-Free Locked Pill Badge
                        if recordingManager.isHandsFreeMode {
                            HStack(spacing: 3.5) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text("LOCKED")
                                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(Color(red: 0.20, green: 0.90, blue: 0.55))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.20, green: 0.90, blue: 0.55).opacity(0.18))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color(red: 0.20, green: 0.90, blue: 0.55).opacity(0.4), lineWidth: 0.8)
                                    )
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // C. Active Dictation Mode Pill Badge
                        if modeManager.currentMode == .auto {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    modeManager.togglePicker()
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 1.0))
                                    Text("Auto: \(modeManager.effectiveMode.rawValue)")
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white.opacity(0.90))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        } else if modeManager.currentMode != .defaultMode {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    modeManager.togglePicker()
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: modeManager.currentMode.iconName)
                                        .font(.system(size: 8.5, weight: .semibold))
                                    Text(modeManager.currentMode.rawValue)
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                        
                        // D. Live Text Preview / Status
                        Group {
                            if !recordingManager.streamingText.isEmpty {
                                Text(recordingManager.streamingText)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.96))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                    .frame(maxWidth: 320, alignment: .leading)
                                    .transition(.opacity)
                            } else if recordingManager.isProcessing {
                                Text("Processing...")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                    .transition(.opacity)
                            } else {
                                Text("Listening...")
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                    .transition(.opacity)
                            }
                        }
                        
                        // E. Silky Dynamic Audio Waveform Bars
                        HStack(spacing: 2.2) {
                            ForEach(0..<barCount, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                waveformGradientStart,
                                                waveformGradientEnd
                                            ],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 2.5, height: barHeight(for: i))
                            }
                        }
                        .frame(height: 20)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .fixedSize(horizontal: true, vertical: true)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recordingManager.isHandsFreeMode)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recordingManager.isProcessing)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recordingManager.streamingText)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: modeManager.currentMode)
            }
            .frame(height: 42)
        }
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
        .onChange(of: recordingManager.isRecording) { _, isRecording in
            if isRecording {
                startAnimation()
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    // MARK: - Theme Colors
    
    private var accentColor: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.20, green: 0.90, blue: 0.55) // Emerald cyan
        } else {
            return Color(red: 0.28, green: 0.65, blue: 1.0) // Wispr Flow Electric Blue
        }
    }
    
    private var waveformGradientStart: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.15, green: 0.75, blue: 0.45)
        } else {
            return Color(red: 0.25, green: 0.60, blue: 1.0)
        }
    }
    
    private var waveformGradientEnd: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.35, green: 0.95, blue: 0.65)
        } else {
            return Color(red: 0.35, green: 0.88, blue: 0.98)
        }
    }
    
    // MARK: - Waveform Math with Silky Asymmetric Attack & Decay
    
    private func barHeight(for index: Int) -> CGFloat {
        let norm = Double(index) / Double(barCount)
        
        let wave1 = sin(wavePhase + norm * 5.2) * 0.45
        let wave2 = sin(wavePhase * 1.35 + norm * 3.6) * 0.35
        let combined = abs(wave1 + wave2)
        
        // Amplitude-scaled height with 3.0 min floor and 20.0 max ceiling
        let height = max(3.0, min(20.0, combined * displayedAmplitude * 22.0))
        return CGFloat(height)
    }
    
    private func startAnimation() {
        stopAnimation()
        displayedAmplitude = 0.30
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
            wavePhase += 0.11
            let liveAmp = Double(recordingManager.audioManager.currentAmplitude) * 5.5
            let target = max(0.20, min(1.0, liveAmp))
            
            // Asymmetric Exponential Moving Average: Fast attack (0.35) for instant voice response,
            // smooth decay (0.12) to eliminate jitter
            let smoothingFactor = target > displayedAmplitude ? 0.35 : 0.12
            displayedAmplitude += (target - displayedAmplitude) * smoothingFactor
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
