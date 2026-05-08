import SwiftUI
import AppKit

// AppDelegate holds the strong reference to the floating pill window
class AppDelegate: NSObject, NSApplicationDelegate {
    var pillWindow: FloatingPillWindow?
    
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
    var body: some View {
        Form {
            Text("Settings will go here")
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
