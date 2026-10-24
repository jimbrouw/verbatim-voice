import Foundation
import AppKit
import Combine

public struct DictationRecord: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let wordCount: Int
    public let appName: String?
    public let appBundleID: String?
    public let mode: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        appName: String? = nil,
        appBundleID: String? = nil,
        mode: String = "Default"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count
        self.appName = appName
        self.appBundleID = appBundleID
        self.mode = mode
    }
}

public class HistoryManager: ObservableObject {
    public static let shared = HistoryManager()
    
    @Published public private(set) var records: [DictationRecord] = []
    @Published public private(set) var todayWordCount: Int = 0
    
    private let fileName = "history.json"
    private let queue = DispatchQueue(label: "com.verbatim.history-manager", qos: .utility)
    
    private init() {
        loadHistory()
    }
    
    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Voice&", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
    
    public func record(text: String, app: NSRunningApplication?, mode: String = "Default") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let record = DictationRecord(
            text: trimmed,
            appName: app?.localizedName,
            appBundleID: app?.bundleIdentifier,
            mode: mode
        )
        
        queue.async { [weak self] in
            guard let self = self else { return }
            var list = self.records
            list.insert(record, at: 0)
            
            // Limit to most recent 500 records
            if list.count > 500 {
                list = Array(list.prefix(500))
            }
            
            let count = self.calculateTodayWords(from: list)
            
            DispatchQueue.main.async {
                self.records = list
                self.todayWordCount = count
            }
            
            self.saveHistory(records: list)
        }
    }
    
    private func calculateTodayWords(from list: [DictationRecord]) -> Int {
        let calendar = Calendar.current
        let today = Date()
        return list.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
            .reduce(0) { $0 + $1.wordCount }
    }
    
    private func saveHistory(records: [DictationRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: historyFileURL)
        }
    }
    
    private func loadHistory() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? Data(contentsOf: self.historyFileURL) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([DictationRecord].self, from: data) {
                let count = self.calculateTodayWords(from: decoded)
                DispatchQueue.main.async {
                    self.records = decoded
                    self.todayWordCount = count
                }
            }
        }
    }
    
    public func clearHistory() {
        queue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.records = []
                self.todayWordCount = 0
            }
            self.saveHistory(records: [])
        }
    }
}
