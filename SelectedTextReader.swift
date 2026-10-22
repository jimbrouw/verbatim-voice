import Cocoa
import ApplicationServices

/// Captures highlighted / selected text across macOS applications.
/// Uses macOS Accessibility APIs first, falling back to non-destructive clipboard simulation (Cmd+C).
public class SelectedTextReader {
    public static let shared = SelectedTextReader()
    
    private init() {}
    
    /// Reads currently selected text across any active application.
    /// - Parameter completion: Called with the extracted text or nil if no text was selected.
    public func getSelectedText(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            // 1. First attempt: macOS Accessibility API (zero side effects)
            if let axText = self.readViaAccessibility(), !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    completion(axText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return
            }
            
            // 2. Second attempt: Simulated Cmd+C with clipboard preservation
            self.readViaSimulatedCopy { copyText in
                DispatchQueue.main.async {
                    if let text = copyText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }
    
    /// Async/await variant of getSelectedText
    @discardableResult
    public func getSelectedText() async -> String? {
        await withCheckedContinuation { continuation in
            getSelectedText { text in
                continuation.resume(returning: text)
            }
        }
    }
    
    // MARK: - Method 1: Accessibility API
    
    private func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        
        // Try getting the system-wide focused element directly
        var status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        
        // If that failed, locate the focused element via the frontmost application
        if status != .success || focusedElementValue == nil {
            var focusedAppValue: AnyObject?
            status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)
            
            var targetApp: AXUIElement?
            if status == .success, let app = focusedAppValue {
                targetApp = (app as! AXUIElement)
            } else if let frontApp = NSWorkspace.shared.frontmostApplication {
                targetApp = AXUIElementCreateApplication(frontApp.processIdentifier)
            }
            
            if let app = targetApp {
                _ = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            }
        }
        
        guard let elementObj = focusedElementValue else {
            return nil
        }
        let focusedElement = elementObj as! AXUIElement
        
        // 1. Try kAXSelectedTextAttribute
        var selectedTextValue: AnyObject?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let text = selectedTextValue as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        
        // 2. Try kAXSelectedTextRangeAttribute combined with kAXValueAttribute
        var rangeValue: AnyObject?
        var range = CFRange(location: kCFNotFound, length: 0)
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rVal = rangeValue, CFGetTypeID(rVal) == AXValueGetTypeID() {
            let axVal = rVal as! AXValue
            if AXValueGetType(axVal) == .cfRange {
                AXValueGetValue(axVal, .cfRange, &range)
            }
        }
        
        if range.location != kCFNotFound && range.length > 0 {
            var textValue: AnyObject?
            if AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &textValue) == .success {
                let fullString: String? = (textValue as? String) ?? (textValue as? NSAttributedString)?.string
                if let str = fullString {
                    let nsStr = str as NSString
                    let loc = min(max(0, range.location), nsStr.length)
                    let len = min(max(0, range.length), nsStr.length - loc)
                    if len > 0 {
                        let substring = nsStr.substring(with: NSRange(location: loc, length: len))
                        if !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return substring
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Method 2: Non-destructive Clipboard Simulation (Cmd+C)
    
    private func readViaSimulatedCopy(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        
        // Preserve existing clipboard state
        let originalChangeCount = pasteboard.changeCount
        let backupItems: [[(NSPasteboard.PasteboardType, Data)]] = {
            guard let items = pasteboard.pasteboardItems else { return [] }
            return items.compactMap { item in
                let typesData = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                    if let data = item.data(forType: type) {
                        return (type, data)
                    }
                    return nil
                }
                return typesData.isEmpty ? nil : typesData
            }
        }()
        
        // Post Cmd+C keystroke
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 8 // 'C' key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false) else {
            completion(nil)
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = []
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        // Poll for clipboard change up to 150ms
        let maxWaitIntervals = 15
        let intervalTime = 0.01 // 10ms
        var elapsed = 0
        
        func poll() {
            if pasteboard.changeCount != originalChangeCount {
                let capturedText = pasteboard.string(forType: .string)
                self.restoreClipboard(backupItems, to: pasteboard)
                completion(capturedText)
                return
            }
            
            elapsed += 1
            if elapsed < maxWaitIntervals {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + intervalTime) {
                    poll()
                }
            } else {
                // Timeout reached, restore original clipboard and finish
                self.restoreClipboard(backupItems, to: pasteboard)
                completion(nil)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + intervalTime) {
            poll()
        }
    }
    
    private func restoreClipboard(_ backupItems: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        guard !backupItems.isEmpty else { return }
        pasteboard.clearContents()
        var objectsToWrite: [NSPasteboardItem] = []
        for itemData in backupItems {
            let pbItem = NSPasteboardItem()
            for (type, data) in itemData {
                pbItem.setData(data, forType: type)
            }
            objectsToWrite.append(pbItem)
        }
        pasteboard.writeObjects(objectsToWrite)
    }
}
