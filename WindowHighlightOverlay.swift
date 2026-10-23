import AppKit
import SwiftUI

/// Draws a glowing electric blue selection border around the frontmost application window
/// during voice dictation — matching Wispr Flow's signature active-window highlight.
public class WindowHighlightOverlay: NSPanel {
    public static let shared = WindowHighlightOverlay()
    
    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.alphaValue = 0
        
        let hostingView = NSHostingView(rootView: WindowBorderHighlightView())
        self.contentView = hostingView
    }
    
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }
    
    public func show() {
        guard let windowRect = Self.getFocusedWindowRect() else {
            // NEVER fallback to full screen! Only highlight the actual application window.
            return
        }
        
        // Add a 2pt margin so the border hugs the target window cleanly
        let padding: CGFloat = 2
        let borderRect = NSRect(
            x: windowRect.origin.x - padding,
            y: windowRect.origin.y - padding,
            width: windowRect.size.width + (padding * 2),
            height: windowRect.size.height + (padding * 2)
        )
        
        present(at: borderRect)
    }
    
    private func present(at frame: NSRect) {
        self.setFrame(frame, display: true)
        self.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1.0
        }
    }
    
    public func hide() {
        guard self.isVisible, self.alphaValue > 0 else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
    
    private static func getFocusedWindowRect() -> NSRect? {
        guard var frontApp = NSWorkspace.shared.frontmostApplication,
              let primaryScreen = NSScreen.screens.first else {
            return nil
        }
        
        // If Voice& itself happens to be reported as frontmost, find the actual target app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            if let target = NSWorkspace.shared.runningApplications.first(where: {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }) {
                frontApp = target
            }
        }
        
        let screenHeight = primaryScreen.frame.height
        let targetPID = frontApp.processIdentifier
        
        // 1. Try CoreGraphics Window List (most reliable across all macOS apps: Electron, Chrome, Notes, Slack, etc.)
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowList {
                let pid = win[kCGWindowOwnerPID as String] as? Int32
                let layer = win[kCGWindowLayer as String] as? Int ?? -1
                let alpha = win[kCGWindowAlpha as String] as? Double ?? 1.0
                let bounds = win[kCGWindowBounds as String] as? [String: CGFloat]
                
                // Layer 0 is normal standard application windows
                if layer == 0 && pid == targetPID && alpha > 0.5, let b = bounds {
                    let w = b["Width"] ?? 0
                    let h = b["Height"] ?? 0
                    let x = b["X"] ?? 0
                    let y = b["Y"] ?? 0
                    
                    // Filter out small tooltips or auxiliary popups
                    if w > 200 && h > 150 {
                        let cocoaY = screenHeight - y - h
                        return NSRect(x: x, y: cocoaY, width: w, height: h)
                    }
                }
            }
        }
        
        // 2. Fallback to Accessibility API if CGWindowList didn't match
        let appElement = AXUIElementCreateApplication(targetPID)
        var windowValue: AnyObject?
        var status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        if status != .success || windowValue == nil {
            status = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowValue)
        }
        
        if status == .success, let windowObj = windowValue {
            let windowElement = windowObj as! AXUIElement
            var posVal: AnyObject?
            var sizeVal: AnyObject?
            var axPoint = CGPoint.zero
            var axSize = CGSize.zero
            
            if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posVal) == .success,
               let p = posVal, CFGetTypeID(p) == AXValueGetTypeID() {
                AXValueGetValue(p as! AXValue, .cgPoint, &axPoint)
            }
            if AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeVal) == .success,
               let s = sizeVal, CFGetTypeID(s) == AXValueGetTypeID() {
                AXValueGetValue(s as! AXValue, .cgSize, &axSize)
            }
            
            if axSize.width > 200 && axSize.height > 150 {
                let cocoaY = screenHeight - axPoint.y - axSize.height
                return NSRect(x: axPoint.x, y: cocoaY, width: axSize.width, height: axSize.height)
            }
        }
        
        // NEVER fallback to full screen! If no window is found, return nil.
        return nil
    }
}

struct WindowBorderHighlightView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.65, blue: 1.0),
                        Color(red: 0.38, green: 0.85, blue: 1.0),
                        Color(red: 0.22, green: 0.55, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 3.5
            )
            .shadow(color: Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.85), radius: 10, x: 0, y: 0)
            .shadow(color: Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.4), radius: 24, x: 0, y: 0)
            .padding(1)
    }
}
