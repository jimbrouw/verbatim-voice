import Foundation

public class SmartBacktracker {
    public static let shared = SmartBacktracker()
    
    public init() {}
    
    /// Processes spoken text, applying natural-language backtrack erasures and self-corrections.
    public func process(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // 1. Clause erasers ("scratch that", "delete that", etc.)
        text = applyClauseErasers(to: text)
        
        // 2. Correction connectors ("no wait", "actually", "I mean", "no, [X]")
        text = applyCorrectionConnectors(to: text)
        
        // 3. Post-cleanup (duplicate whitespace, orphan commas, sentence capitalization)
        text = cleanPunctuationAndSpacing(text)
        
        return text
    }
    
    // MARK: - 1. Clause Erasers
    
    private func applyClauseErasers(to text: String) -> String {
        var result = text
        
        // Regex patterns for clause erasers
        let eraserPatterns = [
            #"(?:[,\.\s]+)?\b(?:scratch that|delete that|cross that out|never mind|forget that|erase that)\b(?:[,\.\s]+)?"#
        ]
        
        for pattern in eraserPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            
            while true {
                let range = NSRange(result.startIndex..., in: result)
                guard let match = regex.firstMatch(in: result, options: [], range: range) else { break }
                
                let matchRange = Range(match.range, in: result)!
                let beforeMatch = String(result[..<matchRange.lowerBound])
                let afterMatch = String(result[matchRange.upperBound...])
                
                // Find where the preceding clause starts
                // Look backwards from beforeMatch for sentence or clause boundary (. ! ? ; or ,)
                let trimmedBefore = beforeMatch.trimmingCharacters(in: .whitespacesAndNewlines)
                var clauseStart = beforeMatch.startIndex
                
                // If there is an existing sentence terminator, only erase from the last sentence
                if let lastSentenceEnd = trimmedBefore.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;\n"), options: .backwards) {
                    clauseStart = lastSentenceEnd.upperBound
                } else if let lastComma = trimmedBefore.rangeOfCharacter(from: CharacterSet(charactersIn: ","), options: .backwards) {
                    clauseStart = lastComma.upperBound
                } else {
                    // Entire preceding text is the clause to erase
                    clauseStart = beforeMatch.startIndex
                }
                
                let preservedPrefix = String(beforeMatch[..<clauseStart])
                result = preservedPrefix + (preservedPrefix.isEmpty ? "" : " ") + afterMatch
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return result
    }
    
    // MARK: - 2. Correction Connectors
    
    private func applyCorrectionConnectors(to text: String) -> String {
        var result = text
        
        // Patterns where candidate B replaces candidate A:
        // Examples:
        // "Tuesday no wait Wednesday" -> "Wednesday"
        // "for Tuesday, actually Friday" -> "for Friday"
        // "at 3 no wait 4" -> "at 4"
        // "Thursday wait no Friday" -> "Friday"
        // "John, I mean Mike" -> "Mike"
        
        let connectorPatterns = [
            // Single-token replacement: "[wordA] no wait [wordB]"
            #"\b(\w+)[,\s]+\b(?:no wait|wait no|actually|I mean|or rather)\b[,\s]+(\w+)\b"#,
            // "[wordA] no [wordB]" mid-sentence correction e.g. "Tuesday no Wednesday"
            #"\b(\w+)[,\s]+\bno\b[,\s]+(\w+)\b"#
        ]
        
        for pattern in connectorPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            
            while true {
                let nsRange = NSRange(result.startIndex..., in: result)
                guard let match = regex.firstMatch(in: result, options: [], range: nsRange) else { break }
                
                let fullMatchRange = Range(match.range, in: result)!
                
                // Group 2 is the replacement candidate (e.g. "Wednesday" or "Friday")
                if match.numberOfRanges >= 3 {
                    let r2 = match.range(at: 2)
                    if r2.location != NSNotFound {
                        let replacement = (result as NSString).substring(with: r2)
                        result.replaceSubrange(fullMatchRange, with: replacement)
                        continue
                    }
                }
                
                result.replaceSubrange(fullMatchRange, with: "")
            }
        }
        
        return result
    }
    
    // MARK: - 3. Clean Spacing & Capitalization
    
    private func cleanPunctuationAndSpacing(_ text: String) -> String {
        var cleaned = text
        
        // Remove orphan commas at start: ", let's meet" -> "let's meet"
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[,;\.]+\s*"#, with: "", options: .regularExpression)
        
        // Collapse double spaces
        cleaned = cleaned.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        
        // Fix space before punctuation: "word , word" -> "word, word"
        cleaned = cleaned.replacingOccurrences(of: #"\s+([,\.!\?;:])"#, with: "$1", options: .regularExpression)
        
        // Capitalize every sentence start (beginning of string or after . ! ?)
        if let regex = try? NSRegularExpression(pattern: #"(?:^|[\.!\?]\s+)([a-z])"#) {
            let nsRange = NSRange(cleaned.startIndex..., in: cleaned)
            let matches = regex.matches(in: cleaned, options: [], range: nsRange)
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let letterRange = match.range(at: 1)
                    if let swiftRange = Range(letterRange, in: cleaned) {
                        let upper = cleaned[swiftRange].uppercased()
                        cleaned.replaceSubrange(swiftRange, with: upper)
                    }
                }
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
