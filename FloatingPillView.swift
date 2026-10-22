import SwiftUI
import Combine

// MARK: - State color definitions
// Blue = idle, Red/Orange = recording, Amber = processing/thinking, Green = hands-free

struct FloatingPillView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    
    // Waveform animation state
    @State private var wavePhase: Double = 0
    @State private var displayedAmplitude: Double = 0.15
    @State private var animationTimer: Timer?
    
    // Number of waveform bars
    private let barCount = 12
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            
            ZStack {
                // 1. Background pill — dark glassmorphism capsule
                Capsule()
                    .fill(Color(white: 0.1, opacity: 0.92))
                    .overlay(
                        Capsule()
                            .stroke(borderColor.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: glowColor.opacity(0.35), radius: 10, x: 0, y: 2)
                
                HStack(spacing: 8) {
                    // 2. Indicator: Distinct lock icon for Hands-Free mode or colored circle dot
                    if recordingManager.isHandsFreeMode {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.16, green: 0.9, blue: 0.48))
                            .shadow(color: Color(red: 0.16, green: 0.9, blue: 0.48).opacity(0.8), radius: 4)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 10, height: 10)
                            .shadow(color: dotColor.opacity(0.7), radius: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // 3. Text preview slot for real-time word streaming
                    if !recordingManager.streamingText.isEmpty {
                        Text(recordingManager.streamingText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: 180, alignment: .leading)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    
                    // 4. Waveform bars (always visible, amplitude-driven)
                    HStack(spacing: 2) {
                        ForEach(0..<barCount, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(barColor.opacity(0.85))
                                .frame(width: 2.5, height: barHeight(for: i))
                        }
                    }
                    .frame(height: 24)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .fixedSize(horizontal: true, vertical: true)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: recordingManager.isHandsFreeMode)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: recordingManager.streamingText)
        }
        .frame(height: 36)
        .onAppear { startIdleAnimation() }
        .onDisappear { stopAnimation() }
        .onChange(of: recordingManager.isRecording) { _, recording in
            if recording {
                startRecordingAnimation()
            } else {
                startIdleAnimation()
            }
        }
        .onChange(of: recordingManager.isProcessing) { _, _ in
            // Re-render for amber state
        }
    }
    
    // MARK: - Colors
    
    private var dotColor: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.16, green: 0.9, blue: 0.48) // Green
        } else if recordingManager.isRecording {
            return Color(red: 1.0, green: 0.23, blue: 0.19) // Red
        } else if recordingManager.isProcessing {
            return Color(red: 1.0, green: 0.76, blue: 0.03) // Amber
        } else {
            return Color(red: 0.23, green: 0.53, blue: 1.0) // Verbatim blue
        }
    }
    
    private var barColor: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.16, green: 0.9, blue: 0.48) // Green bars
        } else if recordingManager.isRecording {
            return Color(red: 1.0, green: 0.3, blue: 0.25) // Red bars
        } else if recordingManager.isProcessing {
            return Color(red: 1.0, green: 0.76, blue: 0.03) // Amber bars
        } else {
            return Color(red: 0.23, green: 0.53, blue: 1.0).opacity(0.5) // Dim blue
        }
    }
    
    private var borderColor: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.16, green: 0.9, blue: 0.48)
        } else if recordingManager.isRecording {
            return Color(red: 1.0, green: 0.3, blue: 0.25)
        } else if recordingManager.isProcessing {
            return Color(red: 1.0, green: 0.76, blue: 0.03)
        } else {
            return Color.white
        }
    }
    
    private var glowColor: Color {
        if recordingManager.isHandsFreeMode {
            return Color(red: 0.16, green: 0.9, blue: 0.48)
        } else if recordingManager.isRecording {
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        } else if recordingManager.isProcessing {
            return Color(red: 1.0, green: 0.76, blue: 0.03)
        } else {
            return Color(red: 0.23, green: 0.53, blue: 1.0)
        }
    }
    
    // MARK: - Waveform bar heights
    
    private func barHeight(for index: Int) -> CGFloat {
        let norm = Double(index) / Double(barCount)
        
        let wave1 = sin(wavePhase + norm * 6.0) * 0.4
        let wave2 = sin(wavePhase * 1.3 + norm * 4.0) * 0.3
        let combined = abs(wave1 + wave2)
        
        let height = max(2.0, combined * displayedAmplitude * 22.0)
        return CGFloat(height)
    }
    
    // MARK: - Animation control
    
    private func startRecordingAnimation() {
        stopAnimation()
        displayedAmplitude = 0.6
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            wavePhase += 0.08
            let target = Double(recordingManager.audioManager.currentAmplitude) * 4.0
            displayedAmplitude += (max(0.3, min(1.0, target)) - displayedAmplitude) * 0.15
        }
    }
    
    private func startIdleAnimation() {
        stopAnimation()
        displayedAmplitude = 0.15
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            wavePhase += 0.02
            displayedAmplitude = 0.15
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
