import Cocoa
import ApplicationServices

class HotkeyManager: ObservableObject {
    private var eventMonitor: Any?
    private var recordingManager: RecordingManager
    private var isActivationKeyDown = false
    private var activationPressStartedAt: Date?
    private var lastTapReleasedAt: Date?
    private var shouldIgnoreCurrentRelease = false
    
    private let doubleTapWindow: TimeInterval = 0.4
    private let tapMaximumDuration: TimeInterval = 0.25
    
    // Accessibility check result
    @Published var isAccessibilityEnabled: Bool = false
    
    init(recordingManager: RecordingManager) {
        self.recordingManager = recordingManager
        checkAccessibilityPermissions()
        setupGlobalMonitor()
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility Enabled: \(isAccessibilityEnabled)")
    }
    
    private func setupGlobalMonitor() {
        // We monitor .flagsChanged to detect when modifier keys like Fn, Option, or Control are pressed or released.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self = self else { return }
            
            let activationKey = ActivationKey.current
            let isActivationKeyPressed = activationKey.isPressed(in: event.modifierFlags)
            
            if isActivationKeyPressed && !self.isActivationKeyDown {
                self.isActivationKeyDown = true
                self.activationPressStartedAt = Date()
                
                if self.recordingManager.isHandsFreeMode {
                    self.shouldIgnoreCurrentRelease = true
                    DispatchQueue.main.async {
                        self.recordingManager.stopHandsFreeRecording()
                    }
                    return
                }
                
                if let lastTapReleasedAt = self.lastTapReleasedAt,
                   Date().timeIntervalSince(lastTapReleasedAt) <= self.doubleTapWindow {
                    self.lastTapReleasedAt = nil
                    self.shouldIgnoreCurrentRelease = true
                    DispatchQueue.main.async {
                        self.recordingManager.startHandsFreeRecording()
                    }
                } else {
                    // Key pressed (hold-to-record started)
                    DispatchQueue.main.async {
                        self.recordingManager.startRecording()
                    }
                }
            } else if !isActivationKeyPressed && self.isActivationKeyDown {
                self.isActivationKeyDown = false
                let now = Date()
                let pressDuration = self.activationPressStartedAt.map { now.timeIntervalSince($0) } ?? 0
                self.activationPressStartedAt = nil
                
                if self.shouldIgnoreCurrentRelease {
                    self.shouldIgnoreCurrentRelease = false
                    return
                }
                
                if pressDuration <= self.tapMaximumDuration {
                    self.lastTapReleasedAt = now
                } else {
                    self.lastTapReleasedAt = nil
                }
                
                // Key released (hold-to-record ended)
                DispatchQueue.main.async {
                    self.recordingManager.stopRecording()
                }
            }
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
