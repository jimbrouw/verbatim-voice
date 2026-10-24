import Foundation
import AppKit

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
    
    public var dictionaryCount: Int {
        return dictionary.count
    }
    
    public func getDictionaryEntries() -> [(phrase: String, replacement: String)] {
        return dictionary.map { ($0.key, $0.value) }.sorted { $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending }
    }
    
    public func setEntry(phrase: String, replacement: String) {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRep = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else { return }
        dictionary[trimmedPhrase] = trimmedRep.isEmpty ? trimmedPhrase : trimmedRep
        saveDictionary()
    }
    
    public func removeEntry(phrase: String) {
        dictionary.removeValue(forKey: phrase)
        saveDictionary()
    }
    
    public func mergeDictionary(entries: [String: String]) {
        for (key, val) in entries {
            dictionary[key] = val
        }
        saveDictionary()
    }
    
    private func saveDictionary() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Voice&")
        guard let dir = appSupportURL else { return }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dictURL = dir.appendingPathComponent(dictionaryFileName)
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dictURL)
            print("💾 [TextFormatter] Saved dictionary with \(dictionary.count) entries to \(dictURL.path)")
        }
    }
    
    // MARK: - Personal Dictionary
    
    public func loadDictionary() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let voiceAndURL = appSupport?.appendingPathComponent("Voice&/\(dictionaryFileName)")
        let verbatimURL = appSupport?.appendingPathComponent("Verbatim/\(dictionaryFileName)")
        let localDictURL = URL(fileURLWithPath: dictionaryFileName)
        
        var targetURL: URL?
        if let voiceAndURL = voiceAndURL, fileManager.fileExists(atPath: voiceAndURL.path) {
            targetURL = voiceAndURL
        } else if let verbatimURL = verbatimURL, fileManager.fileExists(atPath: verbatimURL.path) {
            targetURL = verbatimURL
        } else if fileManager.fileExists(atPath: localDictURL.path) {
            targetURL = localDictURL
        } else if let voiceAndURL = voiceAndURL {
            createDefaultDictionary(at: voiceAndURL)
            targetURL = voiceAndURL
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
        
        let currentMode = ModeManager.shared.effectiveMode
        
        // Fast-path: Blazing Fast mode bypasses all formatting passes
        if currentMode == .blazingFast {
            let leading = applyContextualLeadingSpace(text: text, beforeText: context.beforeText)
            return FormattedInjection(text: leading, shouldPressEnter: false)
        }
        
        // 1. Wispr Flow Natural-Language Backtracking & Self-Correction pass
        text = SmartBacktracker.shared.process(text)
        guard !text.isEmpty else {
            return FormattedInjection(text: "", shouldPressEnter: false)
        }
        
        // 2. Spoken snippet command expansion ("insert [name]" / "snippet [name]")
        text = applySpokenSnippetCommands(to: text)
        
        // 3. Personal Dictionary & Snippet replacement pass with dynamic macro resolution
        text = applyDictionaryReplacements(to: text)
        
        // 4. Screen Context pass (match exact on-screen casing for technical identifiers)
        text = ScreenContext.shared.harmonizeWithScreenContext(text)
        
        // 5. Dyslexia Phonetic Homophone Disambiguation (unless in Code mode to avoid affecting variable names)
        if currentMode != .code {
            text = DyslexiaTranslator.shared.disambiguateHomophones(text)
        }
        
        // 6. Mode-Specific Formatting (Email, Messaging, Code, Notes)
        text = applyModeFormatting(text: text, mode: currentMode)
        
        // 7. Voice command: "press enter" / "press return" at end of utterance
        let (commandFreeText, shouldPressEnter) = extractPressEnterCommand(from: text)
        text = commandFreeText
        
        guard !text.isEmpty else {
            return FormattedInjection(text: "", shouldPressEnter: shouldPressEnter)
        }
        
        // 8. Context-aware capitalization based on beforeText
        text = applyContextualCapitalization(text: text, beforeText: context.beforeText)
        
        // 9. Context-aware leading space
        text = applyContextualLeadingSpace(text: text, beforeText: context.beforeText)
        
        return FormattedInjection(text: text, shouldPressEnter: shouldPressEnter)
    }
    
    // MARK: - Mode Specific Formatting
    
    private func applyModeFormatting(text: String, mode: DictationMode) -> String {
        var result = text
        switch mode {
        case .messaging:
            // Translate spoken emojis
            let emojiRules: [(String, String)] = [
                (#"\b(?:thumbs up|thumb up)\b"#, "👍"),
                (#"\b(?:thumbs down|thumb down)\b"#, "👎"),
                (#"\b(?:heart|red heart)\b"#, "❤️"),
                (#"\b(?:fire|flame)\b"#, "🔥"),
                (#"\b(?:crying laughing|laughing face|rofl)\b"#, "😂"),
                (#"\b(?:smiling face|smiley face|smile face)\b"#, "😊"),
                (#"\b(?:wink face|winking face|wink)\b"#, "😉"),
                (#"\b(?:party face|celebrate|celebration)\b"#, "🎉"),
                (#"\b(?:folded hands|praying hands|high five)\b"#, "🙏"),
                (#"\b(?:skull face|skull)\b"#, "💀")
            ]
            for (pattern, emoji) in emojiRules {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: emoji)
                }
            }
            
        case .email:
            // Format salutations and sign-offs
            let salutationPatterns = [
                (#"^(Hi|Hello|Hey|Dear)\s+([A-Z][a-z]+)[,\.]?\s*"#, "$1 $2,\n\n"),
                (#"\b(Best regards|Warm regards|Best|Thanks|Thank you|Cheers|Sincerely)[,\.]?\s*$"#, "\n\n$1,")
            ]
            for (pattern, replacement) in salutationPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
                }
            }
            
        case .notes:
            // Convert spoken bullet points into clean markdown list
            result = result.replacingOccurrences(of: #"\b(?:new bullet|bullet point|bullet)\s+"#, with: "\n• ", options: [.regularExpression, .caseInsensitive])
            
        case .code, .defaultMode, .blazingFast, .auto:
            break
        }
        return result
    }
    
    // MARK: - Dynamic Snippets & Macro Expansion
    
    private func resolveSnippetMacros(_ snippet: String) -> String {
        var result = snippet
        let now = Date()
        
        if result.contains("{date}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            result = result.replacingOccurrences(of: "{date}", with: formatter.string(from: now))
        }
        if result.contains("{time}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            result = result.replacingOccurrences(of: "{time}", with: formatter.string(from: now))
        }
        if result.contains("{year}") {
            let year = Calendar.current.component(.year, from: now)
            result = result.replacingOccurrences(of: "{year}", with: "\(year)")
        }
        if result.contains("{clipboard}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{clipboard}", with: clip)
        }
        return result
    }
    
    private func applySpokenSnippetCommands(to text: String) -> String {
        let pattern = #"\b(?:insert|snippet)\s+([a-zA-Z0-9_\-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        var result = text
        
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let targetRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let snippetKey = String(result[targetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let replacement = dictionary.first(where: { $0.key.caseInsensitiveCompare(snippetKey) == .orderedSame })?.value {
                let expanded = resolveSnippetMacros(replacement)
                result.replaceSubrange(fullRange, with: expanded)
            }
        }
        return result
    }
    
    // MARK: - Dictionary Pass
    
    private func applyDictionaryReplacements(to text: String) -> String {
        guard !dictionary.isEmpty else { return text }
        var result = text
        
        for (pattern, rawReplacement) in dictionary {
            let replacement = resolveSnippetMacros(rawReplacement)
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
