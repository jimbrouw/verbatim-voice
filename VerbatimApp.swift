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
        
        // Start the MLX Python server
        PythonServerManager.shared.startServer()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        PythonServerManager.shared.stopServer()
    }
    
    private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        print("🔑 Accessibility Enabled: \(trusted)")
        if !trusted {
            print("⚠️ Accessibility NOT granted — text injection will fail.")
            print("   Please add Verbatim in System Settings → Privacy & Security → Accessibility")
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
        item.button?.title = "V"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Verbatim", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
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
    @AppStorage(ActivationKey.defaultsKey) private var activationKeyRawValue = ActivationKey.function.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verbatim Voice")
                .font(.headline)

            Picker("Activation key", selection: $activationKeyRawValue) {
                ForEach(ActivationKey.allCases) { key in
                    Text(key.displayName).tag(key.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedActivationKey.instructionText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Changes apply immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }

    private var selectedActivationKey: ActivationKey {
        ActivationKey(rawValue: activationKeyRawValue) ?? .function
    }
}
