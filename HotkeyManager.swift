import Cocoa
import ApplicationServices

class HotkeyManager: ObservableObject {
    private var eventMonitor: Any?
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var recordingManager: RecordingManager
    private var isActivationKeyDown = false
    private var activationPressStartedAt: Date?
    private var lastTapReleasedAt: Date?
    private var shouldIgnoreCurrentRelease = false
    
    // Wispr Flow timing constant: DICTATION_DEBOUNCE_DELAY = 500ms
    private let doubleTapWindow: TimeInterval = 0.50
    private let tapMaximumDuration: TimeInterval = 0.30
    
    // Accessibility check result
    @Published var isAccessibilityEnabled: Bool = false
    
    init(recordingManager: RecordingManager) {
        self.recordingManager = recordingManager
        checkAccessibilityPermissions()
        setupEventTapOrMonitor()
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility Enabled: \(isAccessibilityEnabled)")
    }
    
    private func setupEventTapOrMonitor() {
        if isAccessibilityEnabled {
            setupEventTap()
        }
        
        // Auxiliary or fallback monitor if event tap is unavailable
        if eventTapPort == nil {
            setupGlobalMonitor()
        }
    }
    
    private func setupEventTap() {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            print("⚠️ CGEvent.tapCreate could not be created; falling back to NSEvent global monitor")
            return
        }
        
        self.eventTapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        print("🎯 Low-level CGEventTap registered successfully")
    }
    
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Automatically re-enable if macOS disables the tap due to timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = eventTapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Support Escape key (keycode 53) to cancel/commit hands-free mode or dismiss Summary Card
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            
            if keyCode == 53 {
                if SummaryCardWindow.shared.isVisible {
                    DispatchQueue.main.async {
                        SummaryCardWindow.shared.dismiss()
                    }
                    return nil
                }
                if recordingManager.isHandsFreeMode {
                    DispatchQueue.main.async {
                        self.recordingManager.stopHandsFreeRecording()
                    }
                    return nil // swallow Escape
                }
                return Unmanaged.passUnretained(event)
            }
            
            // Option + Space (Keycode 49) triggers Voice& Dyslexia Plain-English Summary HUD
            if keyCode == 49 && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
                triggerPlainEnglishSummary()
                return nil // swallow Space
            }
            return Unmanaged.passUnretained(event)
        }
        
        if type == .flagsChanged {
            let flags = event.flags
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let activationKey = ActivationKey.current
            
            let isTargetKey = activationKey.matches(keyCode: keyCode) || activationKey.isPressed(in: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)))
            let isPressed = activationKey.isPressed(in: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)))
            
            if isTargetKey {
                handleActivationKey(isPressed: isPressed)
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func setupGlobalMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self = self else { return }
            
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    if SummaryCardWindow.shared.isVisible {
                        DispatchQueue.main.async {
                            SummaryCardWindow.shared.dismiss()
                        }
                        return
                    }
                    if self.recordingManager.isHandsFreeMode {
                        DispatchQueue.main.async {
                            self.recordingManager.stopHandsFreeRecording()
                        }
                        return
                    }
                }
                
                if event.keyCode == 49 && event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
                    self.triggerPlainEnglishSummary()
                    return
                }
            }
            
            if event.type == .flagsChanged {
                let activationKey = ActivationKey.current
                let isPressed = activationKey.isPressed(in: event.modifierFlags)
                self.handleActivationKey(isPressed: isPressed)
            }
        }
    }
    
    private func triggerPlainEnglishSummary() {
        if isActivationKeyDown {
            shouldIgnoreCurrentRelease = true
            DispatchQueue.main.async {
                self.recordingManager.cancelRecording()
            }
        }
        
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
    
    private func handleActivationKey(isPressed: Bool) {
        if isPressed && !isActivationKeyDown {
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
        } else if !isPressed && isActivationKeyDown {
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
    
    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
