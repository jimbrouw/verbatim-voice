import Cocoa
import ApplicationServices

public struct AccessibilityContextInfo {
    public let beforeText: String
    public let afterText: String
    public let selectedText: String
    public let bundleIdentifier: String?
    public let role: String?
    
    public init(
        beforeText: String = "",
        afterText: String = "",
        selectedText: String = "",
        bundleIdentifier: String? = nil,
        role: String? = nil
    ) {
        self.beforeText = beforeText
        self.afterText = afterText
        self.selectedText = selectedText
        self.bundleIdentifier = bundleIdentifier
        self.role = role
    }
}

public class AccessibilityContext {
    public static let shared = AccessibilityContext()
    
    private init() {}
    
    /// Returns the currently focused UI element of the active application.
    public func getFocusedElement() -> AXUIElement? {
        var frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            frontApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            })
        }
        guard let app = frontApp else { return nil }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElementValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success,
           let element = focusedElementValue {
            return (element as! AXUIElement)
        }
        
        let systemWide = AXUIElementCreateSystemWide()
        var systemFocusedValue: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &systemFocusedValue) == .success,
           let element = systemFocusedValue {
            return (element as! AXUIElement)
        }
        
        return nil
    }
    
    /// Queries the focused UI element of the active application for surrounding text and context.
    public func getContext() -> AccessibilityContextInfo {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppValue: AnyObject?
        var appElement: AXUIElement?
        
        // 1. Get focused application
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
           let app = focusedAppValue {
            appElement = (app as! AXUIElement)
        } else if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        }
        
        guard let app = appElement else {
            return AccessibilityContextInfo()
        }
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        // 2. Get focused UI element
        var focusedElementValue: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success,
              let element = focusedElementValue else {
            return AccessibilityContextInfo(bundleIdentifier: bundleId)
        }
        
        let focusedElement = element as! AXUIElement
        
        var roleValue: AnyObject?
        let role = (AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleValue) == .success) ? (roleValue as? String) : nil
        
        // 3. Get selected text range (kAXSelectedTextRangeAttribute)
        var selectedRangeValue: AnyObject?
        var range = CFRange(location: kCFNotFound, length: 0)
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
           let rangeVal = selectedRangeValue,
           CFGetTypeID(rangeVal) == AXValueGetTypeID() {
            let axVal = rangeVal as! AXValue
            if AXValueGetType(axVal) == .cfRange {
                AXValueGetValue(axVal, .cfRange, &range)
            }
        }
        
        // 4. Get text content (kAXValueAttribute)
        var textValue: AnyObject?
        var fullText = ""
        if AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &textValue) == .success,
           let text = textValue {
            if let str = text as? String {
                fullText = str
            } else if let attrStr = text as? NSAttributedString {
                fullText = attrStr.string
            }
        }
        
        // 5. Selected text attribute fallback
        var selectedText = ""
        if range.length > 0 {
            var selectedVal: AnyObject?
            if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedVal) == .success,
               let str = selectedVal as? String {
                selectedText = str
            }
        }
        
        // 6. Calculate beforeText and afterText safely around caret
        if range.location != kCFNotFound && range.location >= 0 {
            let nsString = fullText as NSString
            let loc = min(max(0, range.location), nsString.length)
            let len = min(max(0, range.length), nsString.length - loc)
            
            let beforeText = nsString.substring(to: loc)
            let afterText = nsString.substring(from: loc + len)
            if selectedText.isEmpty && len > 0 {
                selectedText = nsString.substring(with: NSRange(location: loc, length: len))
            }
            
            return AccessibilityContextInfo(
                beforeText: beforeText,
                afterText: afterText,
                selectedText: selectedText,
                bundleIdentifier: bundleId,
                role: role
            )
        }
        
        return AccessibilityContextInfo(
            beforeText: "",
            afterText: "",
            selectedText: selectedText,
            bundleIdentifier: bundleId,
            role: role
        )
    }
}
