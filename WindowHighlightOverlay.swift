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
            // If focused window frame could not be determined, fallback to active screen visible frame
            if let screen = NSScreen.screens.first(where: { NSPointInRect(NSEvent.mouseLocation, $0.frame) }) ?? NSScreen.main {
                let insetRect = screen.visibleFrame.insetBy(dx: 4, dy: 4)
                present(at: insetRect)
            }
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
        let systemWide = AXUIElementCreateSystemWide()
        var appValue: AnyObject?
        var appElement: AXUIElement?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
           let app = appValue {
            appElement = (app as! AXUIElement)
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        }
        
        guard let app = appElement else { return nil }
        
        var windowValue: AnyObject?
        var status = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue)
        if status != .success || windowValue == nil {
            status = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &windowValue)
        }
        
        guard status == .success, let windowObj = windowValue else { return nil }
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
        
        guard axSize.width > 80 && axSize.height > 80 else { return nil }
        
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let screenHeight = primaryScreen.frame.height
        let cocoaY = screenHeight - axPoint.y - axSize.height
        
        return NSRect(x: axPoint.x, y: cocoaY, width: axSize.width, height: axSize.height)
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
