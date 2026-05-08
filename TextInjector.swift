import Cocoa
import ApplicationServices

class TextInjector {
    static let shared = TextInjector()
    
    func inject(text: String) {
        guard !text.isEmpty else { return }
        
        // 1. Save current clipboard content to restore it later
        let pasteboard = NSPasteboard.general
        let oldItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        // 2. Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 3. Trigger Command+V
        simulatePaste()
        
        // 4. Restore old clipboard after a brief delay
        if let oldItems = oldItems {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.writeObjects(oldItems)
            }
        }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    /// Alternative method: Direct character typing
    func type(text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text.utf16 {
            // FIX: keyboardSetUnicodeString expects a pointer to the character
            var code = char
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
            event?.post(tap: .cghidEventTap)
            
            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            upEvent?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
            upEvent?.post(tap: .cghidEventTap)
        }
    }
}
