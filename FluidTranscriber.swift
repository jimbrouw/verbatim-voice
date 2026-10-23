import Foundation
import AVFoundation
import CoreML
import Combine
import FluidAudio

public class FluidTranscriber: ObservableObject {
    public static let shared = FluidTranscriber()
    
    @Published public var isReady: Bool = false
    @Published public var isTranscribing: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var statusMessage: String = "Initializing..."
    
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private var decoderState: TdtDecoderState?
    private var initTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "com.verbatim.fluid-transcriber", qos: .userInitiated)
    
    public init() {
        startBackgroundInitialization()
    }
    
    public var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Voice&/Models/FluidAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public func startBackgroundInitialization(version: AsrModelVersion = .v2) {
        guard asrManager == nil, initTask == nil else { return }
        
        initTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.loadOrDownloadModel(version: version)
        }
    }
    
    private func loadOrDownloadModel(version: AsrModelVersion) async {
        let dir = modelsDirectory
        print("🧠 [FluidTranscriber] Initializing CoreML Parakeet-TDT (ANE) in \(dir.path)...")
        
        await MainActor.run {
            self.statusMessage = "Loading Neural Engine ASR..."
        }
        
        do {
            let progressHandler: ProgressHandler = { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                    self?.statusMessage = "Downloading ASR Model: \(Int(progress.fractionCompleted * 100))%"
                }
            }
            
            let loadedModels: AsrModels
            if AsrModels.modelsExist(at: dir, version: version) {
                print("⚡ [FluidTranscriber] Found cached CoreML Parakeet models. Loading...")
                loadedModels = try await AsrModels.load(from: dir, version: version, progressHandler: progressHandler)
            } else {
                print("📥 [FluidTranscriber] Downloading CoreML Parakeet-TDT models...")
                loadedModels = try await AsrModels.downloadAndLoad(
                    to: dir,
                    version: version,
                    progressHandler: progressHandler
                )
            }
            
            let manager = AsrManager(config: .default, models: loadedModels)
            let layers = await manager.decoderLayerCount
            let state = TdtDecoderState.make(decoderLayers: layers)
            
            self.asrModels = loadedModels
            self.asrManager = manager
            self.decoderState = state
            
            await MainActor.run {
                self.isReady = true
                self.statusMessage = "CoreML ASR Ready (~100x RTF)"
            }
            print("🚀 [FluidTranscriber] Native CoreML Parakeet-TDT initialized successfully on ANE!")
        } catch {
            print("❌ [FluidTranscriber] Failed to load CoreML models: \(error)")
            await MainActor.run {
                self.statusMessage = "ASR Load Error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Transcription
    
    public func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            Task {
                // Ensure models are ready before proceeding
                if self.asrManager == nil {
                    print("⏳ [FluidTranscriber] ASR not ready yet, waiting for model load...")
                    if let task = self.initTask {
                        _ = await task.value
                    } else {
                        await self.loadOrDownloadModel(version: .v2)
                    }
                }
                
                guard let manager = self.asrManager else {
                    print("❌ [FluidTranscriber] AsrManager unavailable")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                await MainActor.run { self.isTranscribing = true }
                let startTime = DispatchTime.now()
                
                do {
                    // Check file exists
                    guard FileManager.default.fileExists(atPath: audioURL.path) else {
                        print("❌ [FluidTranscriber] Audio file does not exist at: \(audioURL.path)")
                        await MainActor.run {
                            self.isTranscribing = false
                            completion(nil)
                        }
                        return
                    }
                    
                    var state: TdtDecoderState
                    if let existing = self.decoderState {
                        state = existing
                    } else {
                        let layers = await manager.decoderLayerCount
                        state = TdtDecoderState.make(decoderLayers: layers)
                    }
                    let result = try await manager.transcribe(audioURL, decoderState: &state)
                    
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000.0
                    let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("🎙️ [FluidTranscriber] ASR output in \(String(format: "%.3f", elapsed))s (RTFx: \(String(format: "%.1f", result.rtfx))x): \"\(rawText)\"")
                    
                    let filtered = self.filterHallucinations(rawText)
                    
                    await MainActor.run {
                        self.isTranscribing = false
                        completion(filtered)
                    }
                } catch {
                    print("❌ [FluidTranscriber] Transcription error: \(error)")
                    await MainActor.run {
                        self.isTranscribing = false
                        completion(nil)
                    }
                }
            }
        }
    }
    
    public func transcribe(audioSamples: [Float]) async throws -> String {
        guard let manager = asrManager else {
            throw NSError(domain: "FluidTranscriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "ASR Manager not ready"])
        }
        
        var state: TdtDecoderState
        if let existing = self.decoderState {
            state = existing
        } else {
            let layers = await manager.decoderLayerCount
            state = TdtDecoderState.make(decoderLayers: layers)
        }
        let result = try await manager.transcribe(audioSamples, decoderState: &state)
        return filterHallucinations(result.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    // MARK: - Slop / Hallucination Filtering
    
    private func filterHallucinations(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        
        let slopPhrases = [
            "Thank you.",
            "THANK YOU.",
            "Subtitles by",
            "subtitle by",
            "Please subscribe",
            "subscribe to",
            "Amara.org",
            "*Noises*",
            "*noises*",
            "(mimics sounds)",
            "[BLANK]",
            "[Silence]"
        ]
        
        if slopPhrases.contains(where: { text.contains($0) }) && text.count < 60 {
            print("🗑️ [FluidTranscriber] Filtered hallucination slop: \(text)")
            return ""
        }
        
        let isWrapped = (text.hasPrefix("(") && text.hasSuffix(")")) ||
                        (text.hasPrefix("[") && text.hasSuffix("]")) ||
                        (text.hasPrefix("*") && text.hasSuffix("*"))
        if isWrapped && text.count < 40 {
            print("🗑️ [FluidTranscriber] Filtered sound annotation: \(text)")
            return ""
        }
        
        return text
    }
}
