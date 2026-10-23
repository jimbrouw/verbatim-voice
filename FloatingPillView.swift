import SwiftUI
import Combine

// MARK: - Wispr Flow Voice Interaction Pill
// Electric Blue / Cyan theme — NO RED PILL.
// Features dynamic amplitude-driven audio waveform, pulsing audio indicator, and live streaming text.

struct FloatingPillView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    
    // Waveform rendering state
    @State private var wavePhase: Double = 0
    @State private var displayedAmplitude: Double = 0.2
    @State private var animationTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    
    private let barCount = 14
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // 1. Dark obsidian frosted glass capsule background
                Capsule()
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.13).opacity(0.94))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(0.6),
                                        accentColor.opacity(0.25),
                                        accentColor.opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: accentColor.opacity(0.35), radius: 14, x: 0, y: 4)
                
                HStack(spacing: 10) {
                    // 2. Leading state icon (Hands-free lock, Pasting spinner/check, or pulsating Electric Blue Mic)
                    Group {
                        if recordingManager.isHandsFreeMode {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.20, green: 0.90, blue: 0.55))
                                .shadow(color: Color(red: 0.20, green: 0.90, blue: 0.55).opacity(0.8), radius: 6)
                        } else if recordingManager.isProcessing {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 1.0))
                                .shadow(color: Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.8), radius: 6)
                        } else {
                            // Pulsing glowing blue audio mic
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.28, green: 0.65, blue: 1.0).opacity(0.25))
                                    .frame(width: 20, height: 20)
                                    .scaleEffect(pulseScale)
                                
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 0.35, green: 0.80, blue: 1.0))
                                    .shadow(color: Color(red: 0.30, green: 0.75, blue: 1.0).opacity(0.9), radius: 5)
                            }
                        }
                    }
                    .frame(width: 20, height: 20)
                    
                    // 3. Text preview / Live status slot
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
                    
                    // 4. Wispr Flow fluid dynamic audio waveform bars
                    HStack(spacing: 2.5) {
                        ForEach(0..<barCount, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.25, green: 0.60, blue: 1.0),
                                            Color(red: 0.35, green: 0.88, blue: 0.98)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: 2.5, height: barHeight(for: i))
                        }
                    }
                    .frame(height: 22)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .fixedSize(horizontal: true, vertical: true)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recordingManager.isHandsFreeMode)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recordingManager.isProcessing)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recordingManager.streamingText)
        }
        .frame(height: 42)
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
        .onChange(of: recordingManager.isRecording) { _, isRecording in
            if isRecording {
                startAnimation()
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.35
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    // MARK: - Electric Blue Theme Colors
    
    private var accentColor: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.20, green: 0.90, blue: 0.55) // Emerald cyan
        } else {
            return Color(red: 0.28, green: 0.65, blue: 1.0) // Wispr Flow Electric Blue
        }
    }
    
    // MARK: - Waveform Math (Reactive to Mic RMS Amplitude)
    
    private func barHeight(for index: Int) -> CGFloat {
        let norm = Double(index) / Double(barCount)
        
        let wave1 = sin(wavePhase + norm * 5.5) * 0.45
        let wave2 = sin(wavePhase * 1.4 + norm * 3.8) * 0.35
        let combined = abs(wave1 + wave2)
        
        // Amplitude-scaled height with 3.0 min floor and 20.0 max ceiling
        let height = max(3.0, min(22.0, combined * displayedAmplitude * 24.0))
        return CGFloat(height)
    }
    
    private func startAnimation() {
        stopAnimation()
        displayedAmplitude = 0.35
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { _ in
            wavePhase += 0.12
            let liveAmp = Double(recordingManager.audioManager.currentAmplitude) * 5.0
            let target = max(0.25, min(1.0, liveAmp))
            displayedAmplitude += (target - displayedAmplitude) * 0.25
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
