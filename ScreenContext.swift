import Foundation
import AppKit
import Vision

public class ScreenContext {
    public static let shared = ScreenContext()
    
    private let queue = DispatchQueue(label: "com.verbatim.screen-context", qos: .utility)
    public private(set) var activeKeywords: Set<String> = []
    
    public init() {}
    
    /// Captures the focused window's on-screen text and extracts programming and technical tokens
    public func captureFocusedWindowKeywords(for appPID: pid_t? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Get window list to find focused window ID
            guard let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                return
            }
            
            var targetWindowID: CGWindowID?
            for info in windowListInfo {
                if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                    if let appPID = appPID, pid == appPID {
                        if let wid = info[kCGWindowNumber as String] as? CGWindowID {
                            targetWindowID = wid
                            break
                        }
                    } else if appPID == nil {
                        // Use frontmost on-screen normal window
                        if let layer = info[kCGWindowLayer as String] as? Int, layer == 0 {
                            if let wid = info[kCGWindowNumber as String] as? CGWindowID {
                                targetWindowID = wid
                                break
                            }
                        }
                    }
                }
            }
            
            guard let windowID = targetWindowID else { return }
            
            // 2. Capture window image
            guard let windowImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) else {
                return
            }
            
            // 3. Perform fast Vision OCR
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self, error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else { return }
                
                var foundWords = Set<String>()
                for obs in observations {
                    guard let topCandidate = obs.topCandidates(1).first else { continue }
                    let line = topCandidate.string
                    
                    // Tokenize into words
                    let components = line.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                    for rawToken in components {
                        let token = rawToken.trimmingCharacters(in: CharacterSet.punctuationCharacters)
                        if self.isTechnicalKeyword(token) {
                            foundWords.insert(token)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.activeKeywords = foundWords
                    if !foundWords.isEmpty {
                        print("👁️ [ScreenContext] Extracted \(foundWords.count) on-screen keywords (e.g. \(foundWords.prefix(5).joined(separator: ", ")))")
                    }
                }
            }
            
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            
            let handler = VNImageRequestHandler(cgImage: windowImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    /// Checks if a token looks like a technical keyword (camelCase, snake_case, PascalCase, or code term)
    private func isTechnicalKeyword(_ word: String) -> Bool {
        guard word.count >= 3 && word.count <= 40 else { return false }
        
        // Contains underscore (snake_case)
        if word.contains("_") && !word.hasPrefix("_") && !word.hasSuffix("_") {
            return true
        }
        
        // Contains dot (e.g. file.swift, obj.property)
        if word.contains(".") && !word.hasPrefix(".") && !word.hasSuffix(".") {
            return true
        }
        
        // CamelCase or PascalCase (has uppercase inside word)
        let letters = word.filter { $0.isLetter }
        if letters.count >= 3 {
            let hasLower = letters.contains { $0.isLowercase }
            let hasUpperAfterFirst = letters.dropFirst().contains { $0.isUppercase }
            if hasLower && hasUpperAfterFirst {
                return true
            }
        }
        
        // Acronyms (ALL CAPS >= 3 chars)
        if word.allSatisfy({ $0.isUppercase || $0.isNumber }) && word.count >= 3 {
            return true
        }
        
        return false
    }
    
    /// Replaces case-insensitive matches in text with the exact on-screen casing from active keywords
    public func harmonizeWithScreenContext(_ text: String) -> String {
        guard !activeKeywords.isEmpty else { return text }
        var result = text
        
        for keyword in activeKeywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: keyword)
            }
        }
        
        return result
    }
}
