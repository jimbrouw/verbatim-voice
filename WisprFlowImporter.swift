import Foundation
import SQLite3

public struct WisprImportSummary {
    public let wordsCount: Int
    public let snippetsCount: Int
    public let totalDictionaryCount: Int
}

public class WisprFlowImporter {
    public static let shared = WisprFlowImporter()
    
    private init() {}
    
    /// Default paths where Wispr Flow flow.sqlite may reside
    public var candidateSQLitePaths: [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return [
            appSupport.appendingPathComponent("Wispr Flow/flow.sqlite"),
            appSupport.appendingPathComponent("com.electron.wispr-flow/flow.sqlite")
        ]
    }
    
    /// Checks if a Wispr Flow database is present on this Mac
    public var isWisprFlowInstalled: Bool {
        return candidateSQLitePaths.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    /// Imports vocabulary and snippets from Wispr Flow's SQLite database
    @discardableResult
    public func importFromWisprFlow() -> Result<WisprImportSummary, Error> {
        guard let dbURL = candidateSQLitePaths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .failure(NSError(domain: "WisprFlowImporter", code: 404, userInfo: [NSLocalizedDescriptionKey: "Wispr Flow database not found"]))
        }
        
        var db: OpaquePointer?
        let openStatus = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard openStatus == SQLITE_OK, let database = db else {
            let errorMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unable to open SQLite DB"
            if let db = db { sqlite3_close(db) }
            return .failure(NSError(domain: "WisprFlowImporter", code: Int(openStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg]))
        }
        defer { sqlite3_close(database) }
        
        let query = "SELECT phrase, replacement, manualEntry, isSnippet FROM Dictionary WHERE isDeleted = 0 AND phrase IS NOT NULL AND phrase != '';"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(database))
            return .failure(NSError(domain: "WisprFlowImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
        }
        defer { sqlite3_finalize(statement) }
        
        var importedWords = 0
        var importedSnippets = 0
        var newEntries: [String: String] = [:]
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let phraseCStr = sqlite3_column_text(statement, 0)
            let replacementCStr = sqlite3_column_text(statement, 1)
            let isSnippetInt = sqlite3_column_int(statement, 3)
            
            guard let phraseCStr = phraseCStr else { continue }
            let phrase = String(cString: phraseCStr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            
            let replacement: String
            if let replacementCStr = replacementCStr {
                let repStr = String(cString: replacementCStr).trimmingCharacters(in: .whitespacesAndNewlines)
                replacement = repStr.isEmpty ? phrase : repStr
            } else {
                replacement = phrase
            }
            
            newEntries[phrase] = replacement
            if isSnippetInt == 1 {
                importedSnippets += 1
            } else {
                importedWords += 1
            }
        }
        
        // Merge into TextFormatter's dictionary
        TextFormatter.shared.mergeDictionary(entries: newEntries)
        let totalCount = TextFormatter.shared.dictionaryCount
        
        print("📥 [WisprFlowImporter] Successfully imported \(importedWords) words and \(importedSnippets) snippets from Wispr Flow! Total dictionary size: \(totalCount)")
        return .success(WisprImportSummary(wordsCount: importedWords, snippetsCount: importedSnippets, totalDictionaryCount: totalCount))
    }
}
