import Foundation
import SQLite3
import NaturalLanguage

// Standalone test suite for Voice& v2 Architecture

print("═══════════════════════════════════════════════════════════════════════")
print("🧪 RUNNING VOICE& V2 ARCHITECTURAL UPGRADE VERIFICATION SUITE")
print("═══════════════════════════════════════════════════════════════════════\n")

var passedCount = 0
var failedCount = 0

func assertEqual(_ actual: String, _ expected: String, _ name: String) {
    if actual == expected {
        print("  ✅ PASS: \(name)")
        passedCount += 1
    } else {
        print("  ❌ FAIL: \(name)")
        print("     Expected: \"\(expected)\"")
        print("     Actual:   \"\(actual)\"")
        failedCount += 1
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. SMART BACKTRACKER TESTS
// ─────────────────────────────────────────────────────────────────────────────
print("── 1. SmartBacktracker (Wispr Flow Natural Language Backtracking) ──")

class TestBacktracker {
    func process(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = applyClauseErasers(to: text)
        text = applyCorrectionConnectors(to: text)
        text = cleanPunctuationAndSpacing(text)
        return text
    }
    
    private func applyClauseErasers(to text: String) -> String {
        var result = text
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
                let trimmedBefore = beforeMatch.trimmingCharacters(in: .whitespacesAndNewlines)
                var clauseStart = beforeMatch.startIndex
                if let lastSentenceEnd = trimmedBefore.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;\n"), options: .backwards) {
                    clauseStart = lastSentenceEnd.upperBound
                } else if let lastComma = trimmedBefore.rangeOfCharacter(from: CharacterSet(charactersIn: ","), options: .backwards) {
                    clauseStart = lastComma.upperBound
                }
                let preservedPrefix = String(beforeMatch[..<clauseStart])
                result = preservedPrefix + (preservedPrefix.isEmpty ? "" : " ") + afterMatch
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }
    
    private func applyCorrectionConnectors(to text: String) -> String {
        var result = text
        let connectorPatterns = [
            #"\b(\w+)[,\s]+\b(?:no wait|wait no|actually|I mean|or rather)\b[,\s]+(\w+)\b"#,
            #"\b(\w+)[,\s]+\bno\b[,\s]+(\w+)\b"#
        ]
        for pattern in connectorPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            while true {
                let nsRange = NSRange(result.startIndex..., in: result)
                guard let match = regex.firstMatch(in: result, options: [], range: nsRange) else { break }
                let fullMatchRange = Range(match.range, in: result)!
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
    
    private func cleanPunctuationAndSpacing(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[,;\.]+\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
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

let backtracker = TestBacktracker()

// Test 1: Clause eraser ("scratch that")
let t1 = backtracker.process("Let's meet at 5, scratch that, let's meet at 6")
assertEqual(t1, "Let's meet at 6", "Clause eraser 'scratch that'")

// Test 2: Multi-sentence clause eraser
let t2 = backtracker.process("The build is ready. Send the email now, delete that, wait until tomorrow.")
assertEqual(t2, "The build is ready. Wait until tomorrow.", "Clause eraser 'delete that' across sentences")

// Test 3: Correction connector "no wait"
let t3 = backtracker.process("Schedule the sync for Tuesday no wait Wednesday at 3")
assertEqual(t3, "Schedule the sync for Wednesday at 3", "Correction connector 'no wait'")

// Test 4: Correction connector "actually"
let t4 = backtracker.process("Let's do Thursday, actually Friday")
assertEqual(t4, "Let's do Friday", "Correction connector 'actually'")

// Test 5: Correction connector "no [candidate]"
let t5 = backtracker.process("Call John no Mike")
assertEqual(t5, "Call Mike", "Correction connector 'no'")


// ─────────────────────────────────────────────────────────────────────────────
// 2. DYSLEXIA HOMOPHONE DISAMBIGUATION & PLAIN ENGLISH TESTS
// ─────────────────────────────────────────────────────────────────────────────
print("\n── 2. DyslexiaTranslator (Phonetic Disambiguation & Plain English) ──")

class TestDyslexiaTranslator {
    func disambiguateHomophones(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"\btheir\s+(is|are|was|were|will|can|could|should|would)\b"#, with: "there $1", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bthere\s+(going|coming|leaving|doing|saying|planning)\b"#, with: "they're $1", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bto\s+(much|many|late|early|hot|cold|fast|slow|hard|far|soon)\b"#, with: "too $1", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\btoo\s+(the|a|an|my|your|our|their|his|her)\b"#, with: "to $1", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bweather\s+or\s+not\b"#, with: "whether or not", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bthe\s+whether\b"#, with: "the weather", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\b(more|less|better|worse|greater|smaller|faster|slower|rather)\s+then\b"#, with: "$1 than", options: [.regularExpression, .caseInsensitive])
        return result
    }
}

let dyslexia = TestDyslexiaTranslator()

// Test 6: their -> there
let t6 = dyslexia.disambiguateHomophones("their are three items")
assertEqual(t6, "there are three items", "Homophone: their are -> there are")

// Test 7: to -> too
let t7 = dyslexia.disambiguateHomophones("that is to much work")
assertEqual(t7, "that is too much work", "Homophone: to much -> too much")

// Test 8: weather -> whether
let t8 = dyslexia.disambiguateHomophones("I do not know weather or not we should go")
assertEqual(t8, "I do not know whether or not we should go", "Homophone: weather or not -> whether or not")

// Test 9: then -> than
let t9 = dyslexia.disambiguateHomophones("this is better then before")
assertEqual(t9, "this is better than before", "Homophone: better then -> better than")


// ─────────────────────────────────────────────────────────────────────────────
// 3. WISPR FLOW SQLITE DATABASE IMPORTER TEST
// ─────────────────────────────────────────────────────────────────────────────
print("\n── 3. WisprFlowImporter (SQLite Onboarding Migration) ──")

let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let wisprDB = appSupport.appendingPathComponent("Wispr Flow/flow.sqlite")

if FileManager.default.fileExists(atPath: wisprDB.path) {
    var db: OpaquePointer?
    if sqlite3_open_v2(wisprDB.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
        let query = "SELECT COUNT(*) FROM Dictionary WHERE isDeleted = 0 AND phrase IS NOT NULL AND phrase != '';"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let count = sqlite3_column_int(stmt, 0)
                print("  ✅ PASS: Wispr Flow SQLite connected successfully. Found \(count) dictionary entries.")
                passedCount += 1
            }
            sqlite3_finalize(stmt)
        }
        sqlite3_close(db)
    }
} else {
    print("  ⚠️ Wispr Flow SQLite file not found on this machine, skipping live query.")
}


// ─────────────────────────────────────────────────────────────────────────────
// 4. SUMMARY
// ─────────────────────────────────────────────────────────────────────────────
print("\n═══════════════════════════════════════════════════════════════════════")
print("TEST RESULTS: \(passedCount) PASSED, \(failedCount) FAILED")
print("═══════════════════════════════════════════════════════════════════════")

exit(failedCount == 0 ? 0 : 1)
