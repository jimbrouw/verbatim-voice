import AppKit
import SwiftUI

class FloatingPillWindow: NSPanel {
    init(recordingManager: RecordingManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 130, height: 44),
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
        self.hasShadow = false // We handle shadow in SwiftUI
        self.isMovableByWindowBackground = true
        
        let pillView = FloatingPillView()
            .environmentObject(recordingManager)
        
        let hostingView = NSHostingView(rootView: pillView)
        self.contentView = hostingView
        
        // Position: top-right with padding
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 160
            let y = screen.visibleFrame.maxY - 70
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
