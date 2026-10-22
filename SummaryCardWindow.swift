import AppKit
import SwiftUI

public class SummaryCardWindow: NSPanel {
    public static let shared = SummaryCardWindow()
    
    private let viewModel = SummaryCardViewModel()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
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
        self.isMovableByWindowBackground = true
        
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }
        
        let hostingView = NSHostingView(rootView: SummaryCardView(viewModel: viewModel))
        self.contentView = hostingView
    }
    
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }
    
    /// Displays the card positioned near the cursor, and begins loading a summary for the selected text
    public func show(for text: String, at mouseLocation: NSPoint? = nil) {
        viewModel.loadSummary(for: text)
        positionNearCursor(mouseLocation: mouseLocation ?? NSEvent.mouseLocation)
        self.orderFrontRegardless()
        setupDismissMonitors()
    }
    
    public func showNoTextSelected(at mouseLocation: NSPoint? = nil) {
        viewModel.state = .noTextSelected
        positionNearCursor(mouseLocation: mouseLocation ?? NSEvent.mouseLocation)
        self.orderFrontRegardless()
        setupDismissMonitors()
    }
    
    public func dismiss() {
        viewModel.stopSpeech()
        self.orderOut(nil)
        removeDismissMonitors()
    }
    
    private func positionNearCursor(mouseLocation: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLocation, $0.frame) }) ?? NSScreen.main else {
            return
        }
        
        let windowWidth: CGFloat = 380
        let windowHeight: CGFloat = 300
        let padding: CGFloat = 14
        
        // Offset slightly from cursor: to the right and below
        var x = mouseLocation.x + 12
        var y = mouseLocation.y - windowHeight - 12
        
        // Prevent horizontal spill offscreen
        if x + windowWidth > screen.visibleFrame.maxX - padding {
            x = mouseLocation.x - windowWidth - 12
        }
        x = max(screen.visibleFrame.minX + padding, min(x, screen.visibleFrame.maxX - windowWidth - padding))
        
        // Prevent vertical spill offscreen (flip upward if close to bottom)
        if y < screen.visibleFrame.minY + padding {
            y = mouseLocation.y + 16
        }
        y = max(screen.visibleFrame.minY + padding, min(y, screen.visibleFrame.maxY - windowHeight - padding))
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func setupDismissMonitors() {
        removeDismissMonitors()
        
        // Dismiss when clicking outside the window
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            let clickPoint = NSEvent.mouseLocation
            if !self.frame.contains(clickPoint) {
                DispatchQueue.main.async {
                    self.dismiss()
                }
            }
        }
        
        // Local monitor to intercept Escape
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
                return nil
            }
            return event
        }
    }
    
    private func removeDismissMonitors() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
