import Foundation

// Import or copy the logic to test standalone
public struct AccessibilityContextInfo {
    public let beforeText: String
    public let afterText: String
    public let selectedText: String
    
    public init(beforeText: String = "", afterText: String = "", selectedText: String = "") {
        self.beforeText = beforeText
        self.afterText = afterText
        self.selectedText = selectedText
    }
}

public struct FormattedInjection {
    public let text: String
    public let shouldPressEnter: Bool
}

public class TextFormatterTest {
    private var dictionary: [String: String] = [
        "MLX": "MLX",
        "wispr": "Wispr",
        "verbatim voice": "Verbatim Voice"
    ]
    
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

let tester = TextFormatterTest()

func assertEqual(_ actual: String, _ expected: String, _ name: String) {
    if actual == expected {
        print("✅ PASS: \(name)")
    } else {
        print("❌ FAIL: \(name) - Expected '\(expected)', got '\(actual)'")
        exit(1)
    }
}

func assertBool(_ actual: Bool, _ expected: Bool, _ name: String) {
    if actual == expected {
        print("✅ PASS: \(name)")
    } else {
        print("❌ FAIL: \(name) - Expected \(expected), got \(actual)")
        exit(1)
    }
}

// Test 1: Empty beforeText (Document start) -> Capitalize first word, no leading space
let res1 = tester.format(rawText: "hello world", context: AccessibilityContextInfo(beforeText: ""))
assertEqual(res1.text, "Hello world", "Doc start capitalize & no leading space")
assertBool(res1.shouldPressEnter, false, "Doc start shouldPressEnter is false")

// Test 2: beforeText with period -> Capitalize first word, no leading space if trailing space exists
let res2 = tester.format(rawText: "how are you", context: AccessibilityContextInfo(beforeText: "I am good. "))
assertEqual(res2.text, "How are you", "After period + space capitalize")

// Test 3: beforeText without trailing space -> Prepend space & lowercase if mid-sentence
let res3 = tester.format(rawText: "World", context: AccessibilityContextInfo(beforeText: "Hello"))
assertEqual(res3.text, " world", "Mid-sentence prepend space and lowercase")

// Test 4: beforeText without trailing space but starting with punctuation -> No space prepended
let res4 = tester.format(rawText: ", how are you", context: AccessibilityContextInfo(beforeText: "Hello"))
assertEqual(res4.text, ", how are you", "Punctuation start prevents space")

// Test 5: Voice command 'press enter'
let res5 = tester.format(rawText: "Submit this form press enter", context: AccessibilityContextInfo(beforeText: ""))
assertEqual(res5.text, "Submit this form", "Press enter stripped")
assertBool(res5.shouldPressEnter, true, "Press enter detected")

// Test 6: Voice command alone 'press enter.'
let res6 = tester.format(rawText: "press enter.", context: AccessibilityContextInfo(beforeText: ""))
assertEqual(res6.text, "", "Alone press enter stripped")
assertBool(res6.shouldPressEnter, true, "Alone press enter detected")

// Test 7: Dictionary replacement pass
let res7 = tester.format(rawText: "I love wispr and mlx", context: AccessibilityContextInfo(beforeText: ""))
assertEqual(res7.text, "I love Wispr and MLX", "Dictionary replacement")

print("\n🎉 ALL TESTS PASSED!")
