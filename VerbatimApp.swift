import SwiftUI
import AppKit

// MARK: - AppDelegate: Menubar, LifeCycle & Window Management

class AppDelegate: NSObject, NSApplicationDelegate {
    var pillWindow: FloatingPillWindow?
    var statusItem: NSStatusItem?
    
    // Core state managers
    let recordingManager = RecordingManager()
    var hotkeyManager: HotkeyManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        
        // Initialize hotkey manager
        hotkeyManager = HotkeyManager(recordingManager: recordingManager)
        
        // Hide any default SwiftUI windows
        for window in NSApplication.shared.windows {
            window.close()
        }
        
        showPill()
        setupStatusMenu()
        checkAccessibility()
        
        // Pre-warm in-process CoreML ASR (Apple Neural Engine)
        FluidTranscriber.shared.startBackgroundInitialization()
        
        // 1-Click Wispr Flow Dictionary Auto-Migration
        if WisprFlowImporter.shared.isWisprFlowInstalled && TextFormatter.shared.dictionaryCount <= 3 {
            WisprFlowImporter.shared.importFromWisprFlow()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Zero external python processes to kill — 100% native in-process!
    }
    
    private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        print("🔑 Accessibility Enabled: \(trusted)")
        if !trusted {
            print("⚠️ Accessibility NOT granted — text injection and selection reading will fail.")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
    
    func showPill() {
        guard pillWindow == nil else { return }
        pillWindow = FloatingPillWindow(recordingManager: recordingManager)
        pillWindow?.orderFrontRegardless()
        print("🔵 Floating pill window created and shown")
    }

    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "Voice&") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "Voice&"
            }
        }

        let menu = NSMenu()
        
        // Header with status
        let statusTitle = NSMenuItem(title: "Voice& — Neural Engine Ready", action: nil, keyEquivalent: "")
        statusTitle.isEnabled = false
        menu.addItem(statusTitle)
        
        let statsItem = NSMenuItem(title: "Today: \(HistoryManager.shared.todayWordCount) words dictated", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Modes Submenu
        let modesMenu = NSMenu()
        for mode in DictationMode.allCases {
            let modeItem = NSMenuItem(title: "\(mode.rawValue) (\(mode.shortcutNumber))", action: #selector(selectModeFromMenu(_:)), keyEquivalent: "\(mode.shortcutNumber)")
            modeItem.representedObject = mode
            if ModeManager.shared.currentMode == mode {
                modeItem.state = .on
            }
            modesMenu.addItem(modeItem)
        }
        let modeParent = NSMenuItem(title: "Mode: \(ModeManager.shared.currentMode.rawValue)", action: nil, keyEquivalent: "")
        modeParent.submenu = modesMenu
        menu.addItem(modeParent)
        
        menu.addItem(NSMenuItem(title: "Dyslexia TL;DR (⌥ Space)", action: #selector(showPlainEnglishSummary), keyEquivalent: " "))
        
        if WisprFlowImporter.shared.isWisprFlowInstalled {
            menu.addItem(NSMenuItem(title: "Re-import from Wispr Flow", action: #selector(importWisprFlow), keyEquivalent: "i"))
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Voice&", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func selectModeFromMenu(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? DictationMode {
            ModeManager.shared.selectMode(mode)
            setupStatusMenu()
        }
    }

    @objc private func importWisprFlow() {
        let result = WisprFlowImporter.shared.importFromWisprFlow()
        switch result {
        case .success(let summary):
            print("✅ Imported \(summary.wordsCount) words and \(summary.snippetsCount) snippets from Wispr Flow!")
        case .failure(let error):
            print("❌ Wispr Flow import failed: \(error.localizedDescription)")
        }
    }

    @objc private func showPlainEnglishSummary() {
        let mouseLocation = NSEvent.mouseLocation
        SelectedTextReader.shared.getSelectedText { capturedText in
            DispatchQueue.main.async {
                if let text = capturedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SummaryCardWindow.shared.show(for: text, at: mouseLocation)
                } else {
                    SummaryCardWindow.shared.showNoTextSelected(at: mouseLocation)
                }
            }
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - App Main & Multi-Tab Settings View

@main
struct VerbatimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            Color.clear.frame(width: 0, height: 0)
        }
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(ActivationKey.defaultsKey) private var activationKeyRawValue = ActivationKey.function.rawValue
    @ObservedObject var modeManager = ModeManager.shared
    @ObservedObject var historyManager = HistoryManager.shared
    
    @State private var dictionaryEntries: [(phrase: String, replacement: String)] = []
    @State private var searchDictQuery: String = ""
    @State private var newPhrase: String = ""
    @State private var newReplacement: String = ""
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: General & Hotkeys
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)
            
            // Tab 2: Custom Vocabulary & Snippets
            vocabularyTab
                .tabItem {
                    Label("Dictionary", systemImage: "character.book.closed.fill")
                }
                .tag(1)
            
            // Tab 3: History & Stats
            historyTab
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)
        }
        .padding(16)
        .frame(width: 520, height: 420)
        .onAppear {
            loadDictionary()
        }
    }
    
    // MARK: - Tab 1: General
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice& Dictation Engine")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Activation Hotkey:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Dictation Key", selection: $activationKeyRawValue) {
                    ForEach(ActivationKey.allCases) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(selectedActivationKey.instructionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Dictation Mode:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Mode", selection: Binding(
                    get: { modeManager.currentMode },
                    set: { modeManager.selectMode($0) }
                )) {
                    ForEach(DictationMode.allCases) { mode in
                        Text("\(mode.rawValue) (Key \(mode.shortcutNumber))").tag(mode)
                    }
                }
                
                Text(modeManager.currentMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Dyslexia Assistive Intelligence")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Press ⌥ Space with text highlighted anywhere on macOS to open the Plain English TL;DR translator HUD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Tab 2: Vocabulary & Snippets
    
    private var vocabularyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Personal Dictionary & Snippets (\(dictionaryEntries.count))")
                    .font(.headline)
                Spacer()
                if WisprFlowImporter.shared.isWisprFlowInstalled {
                    Button("Re-import Wispr Flow") {
                        WisprFlowImporter.shared.importFromWisprFlow()
                        loadDictionary()
                    }
                    .font(.caption)
                }
            }
            
            // Search field
            TextField("Search vocabulary...", text: $searchDictQuery)
                .textFieldStyle(.roundedBorder)
            
            // Entries Table / List
            List {
                ForEach(filteredEntries, id: \.phrase) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.phrase)
                                .font(.system(size: 12, weight: .semibold))
                            Text(entry.replacement)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            TextFormatter.shared.removeEntry(phrase: entry.phrase)
                            loadDictionary()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: 180)
            
            // Add New Entry Form
            HStack(spacing: 8) {
                TextField("Spoken Phrase", text: $newPhrase)
                    .textFieldStyle(.roundedBorder)
                TextField("Replacement / Snippet", text: $newReplacement)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    guard !newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    TextFormatter.shared.setEntry(phrase: newPhrase, replacement: newReplacement)
                    newPhrase = ""
                    newReplacement = ""
                    loadDictionary()
                }
                .disabled(newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    // MARK: - Tab 3: History
    
    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dictation History")
                    .font(.headline)
                Spacer()
                Text("Today: \(historyManager.todayWordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Clear") {
                    historyManager.clearHistory()
                }
                .font(.caption)
                .disabled(historyManager.records.isEmpty)
            }
            
            if historyManager.records.isEmpty {
                VStack {
                    Spacer()
                    Text("No dictations logged yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(historyManager.records) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.appName ?? "Desktop")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.28, green: 0.65, blue: 1.0))
                            
                            Text("• \(item.mode)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text(item.timestamp, style: .time)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        
                        Text(item.text)
                            .font(.system(size: 12))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
    }
    
    private var filteredEntries: [(phrase: String, replacement: String)] {
        if searchDictQuery.isEmpty {
            return dictionaryEntries
        } else {
            return dictionaryEntries.filter {
                $0.phrase.localizedCaseInsensitiveContains(searchDictQuery) ||
                $0.replacement.localizedCaseInsensitiveContains(searchDictQuery)
            }
        }
    }
    
    private func loadDictionary() {
        dictionaryEntries = TextFormatter.shared.getDictionaryEntries()
    }
    
    private var selectedActivationKey: ActivationKey {
        ActivationKey(rawValue: activationKeyRawValue) ?? .function
    }
}
