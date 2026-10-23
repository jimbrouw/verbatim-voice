import Cocoa
import ApplicationServices

class TextInjector {
    static let shared = TextInjector()
    
    // MARK: - Direct Accessibility Word-by-Word Typing
    
    /// Checks if the focused element allows inserting text at the caret
    func canUseAXInjection(on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        return status == .success && settable.boolValue
    }
    
    /// Injects a single word token directly at the caret without touching the clipboard
    func injectTokenDirectly(_ token: String, to element: AXUIElement) -> Bool {
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, token as CFTypeRef)
        return status == .success
    }
    
    // MARK: - Tokenization
    
    func tokenizeIntoWords(text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        var inWhitespace = false
        
        for char in text {
            if char.isWhitespace {
                currentToken.append(char)
                inWhitespace = true
            } else {
                if inWhitespace {
                    tokens.append(currentToken)
                    currentToken = ""
                    inWhitespace = false
                }
                currentToken.append(char)
            }
        }
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }
        return tokens
    }
    
    // MARK: - Pasteboard Fallback Injection
    
    func injectViaPasteboard(text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let savedItems = backupPasteboard(pasteboard)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        usleep(30_000)
        simulatePaste()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restorePasteboard(savedItems, to: pasteboard)
        }
    }
    
    func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09 // 'V' key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cgSessionEventTap)
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000)
        keyUp.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    func postReturnKey() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKeyCode: CGKeyCode = 0x24 // Return
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = []
        keyUp.flags = []
        
        keyDown.post(tap: .cgSessionEventTap)
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000)
        keyUp.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    // MARK: - Clipboard Preservation
    
    func backupPasteboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
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
    }
    
    func restorePasteboard(_ backup: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        guard !backup.isEmpty else { return }
        pasteboard.clearContents()
        var objectsToWrite: [NSPasteboardItem] = []
        for itemData in backup {
            let pbItem = NSPasteboardItem()
            for (type, data) in itemData {
                pbItem.setData(data, forType: type)
            }
            objectsToWrite.append(pbItem)
        }
        pasteboard.writeObjects(objectsToWrite)
    }
}
