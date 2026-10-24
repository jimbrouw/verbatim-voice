import Cocoa
import ApplicationServices

class HotkeyManager: ObservableObject {
    private var eventMonitor: Any?
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    
    private var recordingManager: RecordingManager
    private var isActivationKeyDown = false
    private var activationPressStartedAt: Date?
    private var lastTapReleasedAt: Date?
    private var quickTapGraceWorkItem: DispatchWorkItem?
    private var isPromotedToHandsFree = false
    private var isDoubleTapSecondPress = false
    
    // Monologue 600ms effective double-tap / silent-discard window
    private let minimumHoldDuration: TimeInterval = 0.40 // <0.4s is a quick tap candidate
    private let doubleTapGraceWindow: TimeInterval = 0.60 // 600ms window to double-tap or silently discard
    
    // Accessibility check result
    @Published var isAccessibilityEnabled: Bool = false
    
    init(recordingManager: RecordingManager) {
        self.recordingManager = recordingManager
        checkAccessibilityPermissions()
        startEventTapThread()
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("🔑 [HotkeyManager] Accessibility Enabled: \(isAccessibilityEnabled)")
    }
    
    // MARK: - Dedicated EventTap Thread
    
    private func startEventTapThread() {
        guard isAccessibilityEnabled else {
            print("⚠️ [HotkeyManager] Accessibility not granted, using NSEvent global monitor fallback")
            setupGlobalMonitor()
            return
        }
        
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            self.setupEventTapOnCurrentThread()
            CFRunLoopRun()
        }
        thread.name = "com.verbatim.key-event-tap"
        thread.qualityOfService = .userInteractive
        self.tapThread = thread
        thread.start()
    }
    
    private func setupEventTapOnCurrentThread() {
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
            print("⚠️ [HotkeyManager] CGEvent.tapCreate failed; falling back to global monitor")
            DispatchQueue.main.async { self.setupGlobalMonitor() }
            return
        }
        
        self.eventTapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        print("🎯 [HotkeyManager] Low-level CGEventTap running on dedicated thread")
    }
    
    // MARK: - Event Handler
    
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Auto-reconnect if macOS disables the tap under heavy load or timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("⚠️ [HotkeyManager] Event tap disabled by macOS (\(type.rawValue)), auto-re-enabling...")
            if let port = eventTapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            // Synthesize key release if modifier got stuck
            if isActivationKeyDown {
                reconcileStaleModifiers()
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Key Down Events (Esc, Spacebar)
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            
            // 1. Escape (Keycode 53) -> Instant Discard / Cancel
            if keyCode == 53 {
                if ModeManager.shared.isPickerVisible {
                    DispatchQueue.main.async { ModeManager.shared.hidePicker() }
                    return nil
                }
                
                if SummaryCardWindow.shared.isVisible {
                    DispatchQueue.main.async {
                        SummaryCardWindow.shared.dismiss()
                    }
                    return nil // swallow Esc
                }
                
                if recordingManager.isRecording || recordingManager.isHandsFreeMode || quickTapGraceWorkItem != nil {
                    quickTapGraceWorkItem?.cancel()
                    quickTapGraceWorkItem = nil
                    isActivationKeyDown = false
                    isPromotedToHandsFree = false
                    activationPressStartedAt = nil
                    lastTapReleasedAt = nil
                    
                    DispatchQueue.main.async {
                        self.recordingManager.cancelRecording()
                    }
                    print("🚫 [HotkeyManager] Escape pressed — dictation aborted")
                    return nil // swallow Esc
                }
                return Unmanaged.passUnretained(event)
            }
            
            // 2. Mode Picker selection with numbers 0-6 while picker is visible
            if ModeManager.shared.isPickerVisible && (recordingManager.isRecording || recordingManager.isHandsFreeMode) {
                let numberMap: [Int64: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6]
                if let num = numberMap[keyCode] {
                    DispatchQueue.main.async {
                        _ = ModeManager.shared.selectByNumber(num)
                        ModeManager.shared.hidePicker()
                    }
                    return nil // swallow number key
                }
            }
            
            // 2. Spacebar (Keycode 49) while holding activation key -> Promote to Hands-Free!
            if keyCode == 49 && isActivationKeyDown && !recordingManager.isHandsFreeMode {
                // If user is holding hotkey and taps spacebar, promote directly to hands-free lock!
                isPromotedToHandsFree = true
                quickTapGraceWorkItem?.cancel()
                quickTapGraceWorkItem = nil
                
                DispatchQueue.main.async {
                    self.recordingManager.startHandsFreeRecording()
                }
                print("🔒 [HotkeyManager] Promoted active recording to Hands-Free Lock via Spacebar")
                return nil // swallow Space
            }
            
            // 3. Option + Space (Keycode 49) when NOT dictating -> Voice& Dyslexia Plain-English HUD
            if keyCode == 49 && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) && !recordingManager.isRecording {
                triggerPlainEnglishSummary()
                return nil // swallow Space
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        // Modifier Key Events (Activation Hotkey & Right Shift Mode Picker)
        if type == .flagsChanged {
            let flags = event.flags
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let activationKey = ActivationKey.current
            
            // Right Shift (Keycode 60) toggles Mode Picker while dictating
            if keyCode == 60 {
                let isShiftDown = flags.contains(.maskShift)
                if isShiftDown && (recordingManager.isRecording || recordingManager.isHandsFreeMode) {
                    DispatchQueue.main.async {
                        ModeManager.shared.togglePicker()
                    }
                    return nil // swallow right shift
                }
            }
            
            let isTargetKey = activationKey.matches(keyCode: keyCode) || activationKey.isPressed(in: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)))
            let isPressed = activationKey.isPressed(in: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)))
            
            if isTargetKey {
                handleActivationKey(isPressed: isPressed)
                // Swallow activation key to prevent macOS focus theft
                return nil
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - Activation Key State Machine (Push-to-Talk & Hands-Free Toggle)
    
    private func handleActivationKey(isPressed: Bool) {
        if isPressed && !isActivationKeyDown {
            // === KEY DOWN ===
            isActivationKeyDown = true
            let now = Date()
            activationPressStartedAt = now
            
            // Case A: User was already recording (in Hands-Free or Toggle Mode) -> Single tap exits and pastes!
            if recordingManager.isRecording || recordingManager.isHandsFreeMode {
                print("🛑 [HotkeyManager] Tapped while recording -> stopping and pasting")
                quickTapGraceWorkItem?.cancel()
                quickTapGraceWorkItem = nil
                lastTapReleasedAt = nil
                DispatchQueue.main.async {
                    self.recordingManager.stopRecording()
                }
                return
            }
            
            // Case B: Second tap within 600ms window -> Lock into Hands-Free!
            if let lastRelease = lastTapReleasedAt, now.timeIntervalSince(lastRelease) <= doubleTapGraceWindow {
                print("🔒 [HotkeyManager] Double-tap detected within \(String(format: "%.0f", now.timeIntervalSince(lastRelease) * 1000))ms -> Locking into Hands-Free Mode!")
                quickTapGraceWorkItem?.cancel()
                quickTapGraceWorkItem = nil
                lastTapReleasedAt = nil
                isDoubleTapSecondPress = true
                
                DispatchQueue.main.async {
                    self.recordingManager.startHandsFreeRecording()
                }
                return
            }
            
            // Case C: New interaction started -> Start recording immediately
            lastTapReleasedAt = nil
            isPromotedToHandsFree = false
            isDoubleTapSecondPress = false
            
            DispatchQueue.main.async {
                self.recordingManager.startRecording()
            }
            
        } else if !isPressed && isActivationKeyDown {
            // === KEY UP ===
            isActivationKeyDown = false
            let now = Date()
            let pressDuration = activationPressStartedAt.map { now.timeIntervalSince($0) } ?? 0
            activationPressStartedAt = nil
            
            // If this press was promoted to hands-free via Spacebar or second double-tap press, ignore the release
            if isPromotedToHandsFree || isDoubleTapSecondPress {
                isPromotedToHandsFree = false
                isDoubleTapSecondPress = false
                return
            }
            
            // If already in hands-free mode, do nothing on release
            if recordingManager.isHandsFreeMode {
                return
            }
            
            // Monologue Rule: Hold > 0.4s is Push-to-Talk. Releasing finishes and pastes.
            if pressDuration >= minimumHoldDuration {
                print("🎙️ [HotkeyManager] Hold-to-Talk finished (\(String(format: "%.2f", pressDuration))s) -> committing")
                lastTapReleasedAt = nil
                DispatchQueue.main.async {
                    self.recordingManager.stopRecording()
                }
            } else {
                // Monologue Rule: Quick tap (<0.4s) candidate
                // Wait for doubleTapGraceWindow (600ms). If 2nd tap arrives, promotes to Hands-Free lock.
                // If NO 2nd tap arrives within 600ms, silently discard (accidental press).
                lastTapReleasedAt = now
                print("⏳ [HotkeyManager] Quick tap (\(String(format: "%.2f", pressDuration))s) -> waiting \(String(format: "%.0f", doubleTapGraceWindow * 1000))ms for double-tap lock confirmation...")
                
                quickTapGraceWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    print("🔇 [HotkeyManager] 600ms grace window elapsed with no 2nd tap -> silently discarding accidental tap")
                    self.lastTapReleasedAt = nil
                    DispatchQueue.main.async {
                        self.recordingManager.silentDiscard()
                    }
                }
                self.quickTapGraceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapGraceWindow, execute: workItem)
            }
        }
    }
    
    // MARK: - Defensive Engineering: Reconcile Stuck Modifiers
    
    private func reconcileStaleModifiers() {
        isActivationKeyDown = false
        activationPressStartedAt = nil
        let src = CGEventSource(stateID: .hidSystemState)
        let optKey: CGKeyCode = 0x3A // Right Option / Alt
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: optKey, keyDown: false) {
            keyUp.flags = []
            keyUp.post(tap: .cghidEventTap)
            print("🛡️ [HotkeyManager] Synthesized modifier key-up to prevent stuck modifier state")
        }
    }
    
    // MARK: - Fallback Global Monitor
    
    private func setupGlobalMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self = self else { return }
            
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    if SummaryCardWindow.shared.isVisible {
                        DispatchQueue.main.async { SummaryCardWindow.shared.dismiss() }
                        return
                    }
                    if self.recordingManager.isRecording || self.recordingManager.isHandsFreeMode {
                        self.quickTapGraceWorkItem?.cancel()
                        self.quickTapGraceWorkItem = nil
                        DispatchQueue.main.async { self.recordingManager.cancelRecording() }
                        return
                    }
                }
                
                if event.keyCode == 49 && self.isActivationKeyDown && !self.recordingManager.isHandsFreeMode {
                    self.isPromotedToHandsFree = true
                    DispatchQueue.main.async { self.recordingManager.startHandsFreeRecording() }
                    return
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
            quickTapGraceWorkItem?.cancel()
            quickTapGraceWorkItem = nil
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
    
    deinit {
        quickTapGraceWorkItem?.cancel()
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
