import SwiftUI
import AVFoundation

public enum SummaryCardState: Equatable {
    case idle
    case loading
    case success(SummaryResult)
    case noTextSelected
    case error(String)
    
    public static func == (lhs: SummaryCardState, rhs: SummaryCardState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.noTextSelected, .noTextSelected):
            return true
        case (.success(let a), .success(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

public class SummaryCardViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published public var state: SummaryCardState = .idle
    @Published public var isSpeaking: Bool = false
    @Published public var copiedFeedback: Bool = false
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    public var onDismiss: (() -> Void)?
    
    public override init() {
        super.init()
        speechSynthesizer.delegate = self
    }
    
    public func loadSummary(for text: String) {
        stopSpeech()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .noTextSelected
            return
        }
        
        state = .loading
        DyslexiaTranslator.shared.summarize(text: trimmed) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let summary):
                self.state = .success(summary)
            case .failure(let error):
                self.state = .error(error.localizedDescription)
            }
        }
    }
    
    public func toggleSpeech() {
        if isSpeaking {
            stopSpeech()
            return
        }
        
        guard case .success(let summary) = state else { return }
        
        // Assemble text to speak: TL;DR first, then key points
        var speechString = "TL;DR: " + summary.tldr
        if !summary.keyPoints.isEmpty {
            speechString += ". Key points: " + summary.keyPoints.joined(separator: ". ")
        }
        
        let utterance = AVSpeechUtterance(string: speechString)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95 // slightly relaxed rate for dyslexic processing
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        if let preferredVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = preferredVoice
        }
        
        isSpeaking = true
        speechSynthesizer.speak(utterance)
    }
    
    public func stopSpeech() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
    
    public func copyToClipboard() {
        guard case .success(let summary) = state else { return }
        var export = "TL;DR: \(summary.tldr)\n\nKEY POINTS:\n"
        for point in summary.keyPoints {
            export += "• \(point)\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(export.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
        
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.copiedFeedback = false
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}

public struct SummaryCardView: View {
    @ObservedObject var viewModel: SummaryCardViewModel
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.38, green: 0.65, blue: 1.0))
                    Text("PLAIN ENGLISH TL;DR")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(Color(red: 0.38, green: 0.65, blue: 1.0))
                }
                
                Spacer()
                
                // Close button
                Button(action: {
                    viewModel.stopSpeech()
                    viewModel.onDismiss?()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Content region
            Group {
                switch viewModel.state {
                case .idle:
                    EmptyView()
                    
                case .loading:
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .colorScheme(.dark)
                            Text("Translating to Plain English...")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        // Shimmer placeholder bars
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 14)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.08))
                                .frame(maxWidth: 240, maxHeight: 14)
                        }
                    }
                    .padding(16)
                    
                case .noTextSelected:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "cursorarrow.and.square.on.square.dashed")
                                .font(.system(size: 18))
                                .foregroundColor(Color.orange)
                            Text("No Text Highlighted")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Text("Highlight any sentence or paragraph across any macOS app and press ⌥ Space to generate an instant Plain English summary.")
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .lineSpacing(3)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(16)
                    
                case .error(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.red)
                            Text("Translation Error")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Text(message)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(16)
                    
                case .success(let summary):
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            // 1. One-Sentence TL;DR (Prominent, High-Legibility)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(summary.tldr)
                                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                    .lineSpacing(4)
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.18, green: 0.26, blue: 0.42).opacity(0.45))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.38, green: 0.65, blue: 1.0).opacity(0.25), lineWidth: 1)
                                    )
                            )
                            
                            // 2. Key Action Bullets
                            if !summary.keyPoints.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("KEY POINTS")
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .tracking(0.6)
                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    ForEach(summary.keyPoints, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(Color(red: 0.38, green: 0.85, blue: 0.65))
                                                .frame(width: 5, height: 5)
                                                .padding(.top, 6)
                                            Text(point)
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .lineSpacing(3)
                                                .foregroundColor(.white.opacity(0.92))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxHeight: 280)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Footer Action Bar
            HStack(alignment: .center, spacing: 10) {
                // Audio Read Aloud button
                Button(action: {
                    viewModel.toggleSpeech()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.isSpeaking ? "Stop" : "Read Aloud")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(viewModel.isSpeaking ? Color.red.opacity(0.3) : Color.white.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(viewModel.isSpeaking ? Color.red.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled({
                    if case .success = viewModel.state { return false }
                    return true
                }())
                
                // Copy button
                Button(action: {
                    viewModel.copyToClipboard()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(viewModel.copiedFeedback ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundColor(.white.opacity(viewModel.copiedFeedback ? 1.0 : 0.8))
                }
                .buttonStyle(.plain)
                .disabled({
                    if case .success = viewModel.state { return false }
                    return true
                }())
                
                Spacer()
                
                // Latency and model badge
                if case .success(let summary) = viewModel.state {
                    Text(String(format: "%.2fs • 100%% Local", summary.latency))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    Text("Voice& ⌥ Space")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.25))
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
    }
}
