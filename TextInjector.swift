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
    
    // MARK: - Token-by-Token Pasteboard Injection
    
    func injectTokenViaPasteboard(_ token: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
        simulatePaste()
    }
    
    func injectViaPasteboard(text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let savedItems = backupPasteboard(pasteboard)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        usleep(20_000)
        simulatePaste()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.restorePasteboard(savedItems, to: pasteboard)
        }
    }
    
    func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdKey: CGKeyCode = 0x37 // 55: Command key
        let vKey: CGKeyCode = 0x09   // 9: 'V' key
        
        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false) else {
            return
        }
        
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []
        
        cmdDown.post(tap: .cghidEventTap)
        usleep(4_000)
        vDown.post(tap: .cghidEventTap)
        usleep(4_000)
        vUp.post(tap: .cghidEventTap)
        usleep(4_000)
        cmdUp.post(tap: .cghidEventTap)
    }
    
    func postReturnKey() {
        let src = CGEventSource(stateID: .hidSystemState)
        let returnKeyCode: CGKeyCode = 0x24 // Return
        
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: returnKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = []
        keyUp.flags = []
        
        keyDown.post(tap: .cghidEventTap)
        usleep(8_000)
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
