import Cocoa
import ApplicationServices

public enum InjectionMode: String {
    case typewriter
    case paste
}

class TextInjector {
    static let shared = TextInjector()
    
    // Default mode: typewriter streaming (words input one at a time like Claude/Gemini)
    var mode: InjectionMode = .typewriter
    
    // Typing delay between words in milliseconds
    var wordDelayMs: UInt32 = 75
    
    func inject(text: String) {
        guard !text.isEmpty else { return }
        
        let context = AccessibilityContext.shared.getContext()
        let formatted = TextFormatter.shared.format(rawText: text, context: context)
        
        if !formatted.text.isEmpty {
            switch mode {
            case .typewriter:
                streamType(text: formatted.text, wordDelayMs: wordDelayMs) { [weak self] in
                    if formatted.shouldPressEnter {
                        usleep(60_000)
                        DispatchQueue.main.async {
                            self?.postReturnKey()
                        }
                    }
                }
                return
                
            case .paste:
                paste(text: formatted.text)
            }
        }
        
        if formatted.shouldPressEnter {
            let delay: TimeInterval = formatted.text.isEmpty ? 0.0 : 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.postReturnKey()
            }
        }
    }
    
    // MARK: - Word-by-Word Streaming Injection
    
    func injectToken(_ token: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
        simulatePaste()
    }
    
    func streamType(text: String, wordDelayMs: UInt32 = 75, completion: (() -> Void)? = nil) {
        let pasteboard = NSPasteboard.general
        let savedItems = backupPasteboard(pasteboard)
        let words = tokenizeIntoWords(text: text)
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            for (index, word) in words.enumerated() {
                self.injectToken(word)
                if index < words.count - 1 && wordDelayMs > 0 {
                    usleep(wordDelayMs * 1000)
                }
            }
            
            // Restore user's previous clipboard after streaming completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.restorePasteboard(savedItems, to: pasteboard)
            }
            completion?()
        }
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
    
    // MARK: - Instant Paste Fallback
    
    func paste(text: String) {
        let pasteboard = NSPasteboard.general
        let savedItems = backupPasteboard(pasteboard)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulatePaste()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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
        
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000)
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
        
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000)
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
