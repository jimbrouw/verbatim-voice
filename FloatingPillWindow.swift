import AppKit
import SwiftUI
import Combine

class FloatingPillWindow: NSPanel {
    private var cancellables = Set<AnyCancellable>()
    
    init(recordingManager: RecordingManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 48),
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
        self.alphaValue = 0
        
        let pillView = FloatingPillView()
            .environmentObject(recordingManager)
        
        let hostingView = NSHostingView(rootView: pillView)
        self.contentView = hostingView
        
        // Position: top-right with padding
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 360
            let y = screen.visibleFrame.maxY - 70
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Auto-show only during active recording, processing, or hands-free mode
        recordingManager.$isRecording
            .combineLatest(recordingManager.$isProcessing, recordingManager.$isHandsFreeMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isProcessing, isHandsFreeMode in
                guard let self = self else { return }
                let shouldBeVisible = isRecording || isProcessing || isHandsFreeMode
                if shouldBeVisible {
                    if self.alphaValue < 1.0 || !self.isVisible {
                        self.orderFrontRegardless()
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.15
                            self.animator().alphaValue = 1.0
                        }
                    }
                } else {
                    if self.isVisible && self.alphaValue > 0 {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.25
                            self.animator().alphaValue = 0
                        }, completionHandler: {
                            if !recordingManager.isRecording && !recordingManager.isProcessing && !recordingManager.isHandsFreeMode {
                                self.orderOut(nil)
                            }
                        })
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
