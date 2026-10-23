import Foundation
import NaturalLanguage

public struct SummaryResult: Equatable {
    public let tldr: String
    public let keyPoints: [String]
    public let raw: String
    public let latency: Double
    public let model: String
}

public class DyslexiaTranslator: ObservableObject {
    public static let shared = DyslexiaTranslator()
    
    public init() {}
    
    // MARK: - Phonetic Homophone Disambiguation & Assistive Intelligence
    
    /// Corrects phonetically ambiguous homophones common in dyslexia and speech recognition
    public func disambiguateHomophones(_ text: String) -> String {
        var result = text
        guard !result.isEmpty else { return result }
        
        // Homophone rules using contextual regex
        let rules: [(pattern: String, replacement: String)] = [
            // their / there / they're
            (#"\btheir\s+(?:is|are|was|were|will|can|could|should|would)\b"#, "there $1"), // replaced below
            (#"\bthere\s+(?:going|coming|leaving|doing|saying)\b"#, "they're $1"),
            
            // to / too / two
            (#"\bto\s+(?:much|many|late|early|hot|cold|fast|slow|hard|far|soon)\b"#, "too $1"),
            (#"\btoo\s+(?:the|a|an|my|your|our|their|his|her)\b"#, "to $1"),
            
            // weather / whether
            (#"\bweather\s+or\s+not\b"#, "whether or not"),
            (#"\bthe\s+whether\b"#, "the weather"),
            
            // then / than
            (#"\b(?:more|less|better|worse|greater|smaller|faster|slower|rather)\s+then\b"#, "$1 than"),
            
            // affect / effect
            (#"\b(?:the|an|any|no)\s+affect\b"#, "$1 effect"),
            (#"\bwill\s+effect\b"#, "will affect"),
            
            // loose / lose
            (#"\b(?:don't|will|might|could)\s+loose\b"#, "$1 lose")
        ]
        
        for rule in rules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.replacement)
            }
        }
        
        // Specific their/there fix with match evaluation
        result = result.replacingOccurrences(of: #"\btheir\s+(is|are|was|were|will|can|could|should|would)\b"#, with: "there $1", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bthere\s+(going|coming|leaving|doing|saying|planning)\b"#, with: "they're $1", options: [.regularExpression, .caseInsensitive])
        
        return result
    }
    
    // MARK: - Plain English Dyslexia Summarization
    
    /// Translates dense or jargon-heavy text into plain English TL;DR and key points (100% Native & Offline)
    public func summarize(text: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Voice&", code: 400, userInfo: [NSLocalizedDescriptionKey: "Text is empty."])))
            return
        }
        
        let start = DispatchTime.now()
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Native offline Apple NaturalLanguage extraction
            let sentences = self.extractSentences(from: trimmed)
            let (tldr, keyPoints) = self.synthesizeSummary(sentences: sentences, fullText: trimmed)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0
            
            let result = SummaryResult(
                tldr: tldr,
                keyPoints: keyPoints,
                raw: trimmed,
                latency: elapsed,
                model: "Native Neural NLP (Offline)"
            )
            
            DispatchQueue.main.async {
                completion(.success(result))
            }
        }
    }
    
    public func summarize(text: String) async throws -> SummaryResult {
        try await withCheckedThrowingContinuation { continuation in
            summarize(text: text) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Native NLP Sentence Tokenization & Bullet Extraction
    
    private func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }
    
    private func synthesizeSummary(sentences: [String], fullText: String) -> (tldr: String, keyPoints: [String]) {
        guard !sentences.isEmpty else {
            return (fullText, [fullText])
        }
        
        // 1. Identify primary summary sentence (TL;DR)
        let primarySentence = sentences.first ?? fullText
        let tldr = simplifyJargon(primarySentence)
        
        // 2. Identify 2-3 key action or factual points
        var points: [String] = []
        for sentence in sentences.dropFirst().prefix(4) {
            let simplified = simplifyJargon(sentence)
            if simplified.count > 15 && !points.contains(simplified) {
                points.append(simplified)
            }
            if points.count >= 3 { break }
        }
        
        if points.isEmpty {
            // Generate bullet points by clauses of the main sentence
            let clauses = primarySentence.components(separatedBy: CharacterSet(charactersIn: ";,"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 10 }
            
            for clause in clauses.prefix(2) {
                points.append(clause)
            }
        }
        
        if points.isEmpty {
            points.append(tldr)
        }
        
        return (tldr, points)
    }
    
    private func simplifyJargon(_ text: String) -> String {
        var simplified = text
        let jargonReplacements: [(String, String)] = [
            (#"\butilize\b"#, "use"),
            (#"\bcommence\b"#, "start"),
            (#"\bterminate\b"#, "end"),
            (#"\bfacilitate\b"#, "help"),
            (#"\bimplement\b"#, "build"),
            (#"\bsubsequently\b"#, "then"),
            (#"\bconsequently\b"#, "so"),
            (#"\bin order to\b"#, "to"),
            (#"\bat this point in time\b"#, "now"),
            (#"\bdue to the fact that\b"#, "because")
        ]
        
        for (jargon, plain) in jargonReplacements {
            simplified = simplified.replacingOccurrences(of: jargon, with: plain, options: [.regularExpression, .caseInsensitive])
        }
        
        return simplified.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
