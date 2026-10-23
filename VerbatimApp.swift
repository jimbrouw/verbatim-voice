import SwiftUI
import AppKit

// AppDelegate holds the strong reference to the floating pill window
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
            print("   Please add Voice& in System Settings → Privacy & Security → Accessibility")
            // Prompt the system dialog
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
    
    func showPill() {
        guard pillWindow == nil else { return } // Only create once
        pillWindow = FloatingPillWindow(recordingManager: recordingManager)
        pillWindow?.orderFrontRegardless()
        print("🔵 Floating pill window created and shown")
    }

    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Voice&"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dyslexia TL;DR (⌥ Space)", action: #selector(showPlainEnglishSummary), keyEquivalent: " "))
        
        if WisprFlowImporter.shared.isWisprFlowInstalled {
            menu.addItem(NSMenuItem(title: "Import from Wispr Flow", action: #selector(importWisprFlow), keyEquivalent: "i"))
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Voice&", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
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

@main
struct VerbatimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            // Empty view since AppDelegate handles our floating window
            Color.clear
                .frame(width: 0, height: 0)
        }
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(ActivationKey.defaultsKey) private var activationKeyRawValue = ActivationKey.option.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice& Assistant")
                .font(.headline)

            Picker("Dictation Key", selection: $activationKeyRawValue) {
                ForEach(ActivationKey.allCases) { key in
                    Text(key.displayName).tag(key.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedActivationKey.instructionText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Dyslexia Accessibility")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Press ⌥ Space with text highlighted anywhere on macOS to open the Plain English TL;DR translator HUD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Changes apply immediately.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 380)
    }

    private var selectedActivationKey: ActivationKey {
        ActivationKey(rawValue: activationKeyRawValue) ?? .option
    }
}
