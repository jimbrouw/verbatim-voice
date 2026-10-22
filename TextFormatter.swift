import Foundation

public struct FormattedInjection {
    public let text: String
    public let shouldPressEnter: Bool
    
    public init(text: String, shouldPressEnter: Bool) {
        self.text = text
        self.shouldPressEnter = shouldPressEnter
    }
}

public class TextFormatter {
    public static let shared = TextFormatter()
    
    private var dictionary: [String: String] = [:]
    private let dictionaryFileName = "dictionary.json"
    
    public init() {
        loadDictionary()
    }
    
    // MARK: - Personal Dictionary
    
    public func loadDictionary() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Verbatim")
        
        let customDictURL = appSupportURL?.appendingPathComponent(dictionaryFileName)
        let localDictURL = URL(fileURLWithPath: dictionaryFileName)
        
        var targetURL: URL?
        if let customDictURL = customDictURL, fileManager.fileExists(atPath: customDictURL.path) {
            targetURL = customDictURL
        } else if fileManager.fileExists(atPath: localDictURL.path) {
            targetURL = localDictURL
        } else if let customDictURL = customDictURL {
            createDefaultDictionary(at: customDictURL)
            targetURL = customDictURL
        }
        
        guard let url = targetURL,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return
        }
        
        self.dictionary = json
        print("📖 Loaded personal dictionary with \(dictionary.count) entries")
    }
    
    private func createDefaultDictionary(at url: URL) {
        let defaultEntries: [String: String] = [
            "MLX": "MLX",
            "wispr": "Wispr",
            "verbatim voice": "Verbatim Voice"
        ]
        
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: defaultEntries, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            print("📝 Created default dictionary template at \(url.path)")
        } catch {
            print("⚠️ Failed to create default dictionary template: \(error)")
        }
    }
    
    // MARK: - Pipeline
    
    public func format(rawText: String, context: AccessibilityContextInfo) -> FormattedInjection {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return FormattedInjection(text: "", shouldPressEnter: false)
        }
        
        // 1. Personal Dictionary replacement pass
        text = applyDictionaryReplacements(to: text)
        
        // 2. Voice command: "press enter" / "press return" at end of utterance
        let (commandFreeText, shouldPressEnter) = extractPressEnterCommand(from: text)
        text = commandFreeText
        
        guard !text.isEmpty else {
            return FormattedInjection(text: "", shouldPressEnter: shouldPressEnter)
        }
        
        // 3. Context-aware capitalization based on beforeText
        text = applyContextualCapitalization(text: text, beforeText: context.beforeText)
        
        // 4. Context-aware leading space
        text = applyContextualLeadingSpace(text: text, beforeText: context.beforeText)
        
        return FormattedInjection(text: text, shouldPressEnter: shouldPressEnter)
    }
    
    // MARK: - Dictionary Pass
    
    private func applyDictionaryReplacements(to text: String) -> String {
        guard !dictionary.isEmpty else { return text }
        var result = text
        
        for (pattern, replacement) in dictionary {
            let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
            let regexPattern = "\\b\(escapedPattern)\\b"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        return result
    }
    
    // MARK: - Voice Command Detection
    
    private func extractPressEnterCommand(from text: String) -> (String, Bool) {
        let pattern = #"(?:[,\s]+)?\bpress\s+(?:enter|return)\b[\.\!\?]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (text, false)
        }
        
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            let matchedRange = match.range
            let nsText = text as NSString
            let cleaned = nsText.replacingCharacters(in: matchedRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (cleaned, true)
        }
        
        return (text, false)
    }
    
    // MARK: - Context-Aware Capitalization
    
    private func applyContextualCapitalization(text: String, beforeText: String) -> String {
        let trimmedBefore = beforeText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isDocOrSentenceStart = trimmedBefore.isEmpty ||
            trimmedBefore.hasSuffix(".") ||
            trimmedBefore.hasSuffix("!") ||
            trimmedBefore.hasSuffix("?")
        
        guard let firstLetterIdx = text.firstIndex(where: { $0.isLetter }) else {
            return text
        }
        
        if isDocOrSentenceStart {
            var result = text
            let upper = String(result[firstLetterIdx]).uppercased()
            result.replaceSubrange(firstLetterIdx...firstLetterIdx, with: upper)
            return result
        } else {
            // Avoid lowercasing uppercase acronyms (e.g. "API", "AI", "NASA")
            let remainder = text[firstLetterIdx...]
            let firstWord = remainder.prefix(while: { $0.isLetter })
            if firstWord.count > 1 && firstWord.allSatisfy({ $0.isUppercase }) {
                return text
            }
            
            var result = text
            let lower = String(result[firstLetterIdx]).lowercased()
            result.replaceSubrange(firstLetterIdx...firstLetterIdx, with: lower)
            return result
        }
    }
    
    // MARK: - Context-Aware Leading Space
    
    private func applyContextualLeadingSpace(text: String, beforeText: String) -> String {
        let beforeEndsInWhitespaceOrNewline = beforeText.isEmpty ||
            beforeText.last?.isWhitespace == true ||
            beforeText.last?.isNewline == true
        
        let startsWithPunctuation = text.first?.isPunctuation == true
        
        if !beforeText.isEmpty && !beforeEndsInWhitespaceOrNewline && !startsWithPunctuation {
            return " " + text
        }
        
        return text
    }
}
