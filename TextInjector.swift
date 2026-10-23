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
    
    // Typing delay between words in milliseconds (35ms gives a fast, natural streaming feel)
    var wordDelayMs: UInt32 = 35
    
    func inject(text: String) {
        guard !text.isEmpty else { return }
        
        // 1. Inspect accessibility context around the caret
        let context = AccessibilityContext.shared.getContext()
        
        // 2. Format text through personal dictionary, voice commands ("press enter"), and context-aware capitalization/spacing
        let formatted = TextFormatter.shared.format(rawText: text, context: context)
        
        // 3. Inject text according to selected mode
        if !formatted.text.isEmpty {
            switch mode {
            case .typewriter:
                streamType(text: formatted.text, wordDelayMs: wordDelayMs) { [weak self] in
                    if formatted.shouldPressEnter {
                        usleep(50_000) // 50ms pause before return
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
        
        // Handle "press enter" voice command for paste mode or empty text
        if formatted.shouldPressEnter {
            let delay: TimeInterval = formatted.text.isEmpty ? 0.0 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.postReturnKey()
            }
        }
    }
    
    // MARK: - Typewriter (Word-by-Word Streaming)
    
    /// Rapidly types text word-by-word with a slight delay, matching Gemini / Claude live chat streaming
    func streamType(text: String, wordDelayMs: UInt32 = 35, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let words = self.tokenizeIntoWords(text: text)
            for (index, word) in words.enumerated() {
                self.sendUnicodeString(word)
                if index < words.count - 1 && wordDelayMs > 0 {
                    usleep(wordDelayMs * 1000)
                }
            }
            completion?()
        }
    }
    
    /// Breaks string into tokens while preserving exact spaces, punctuation, and newlines
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
    
    /// Safely sends Unicode characters to the focused application in chunks
    private func sendUnicodeString(_ string: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Array = Array(string.utf16)
        let maxChunkSize = 20
        var offset = 0
        
        while offset < utf16Array.count {
            let chunkSize = min(maxChunkSize, utf16Array.count - offset)
            var chunk = Array(utf16Array[offset..<(offset + chunkSize)])
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            
            keyDown?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            offset += chunkSize
        }
    }
    
    // MARK: - Instant Paste Fallback
    
    private func paste(text: String) {
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
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        simulatePaste()
        
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
    
    func postReturnKey() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKeyCode: CGKeyCode = 0x24
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    func type(text: String) {
        sendUnicodeString(text)
    }
    
    func injectToken(_ token: String) {
        sendUnicodeString(token)
    }
}
