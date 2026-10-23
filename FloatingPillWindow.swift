import AppKit
import SwiftUI
import Combine

/// Wispr Flow style floating pill HUD anchored at the bottom-center of the screen.
/// Automatically appears with the active-window blue highlight when dictation starts,
/// and smoothly vanishes when dictation is completed and pasted.
class FloatingPillWindow: NSPanel {
    private var cancellables = Set<AnyCancellable>()
    private let targetWidth: CGFloat = 420
    private let targetHeight: CGFloat = 54
    
    init(recordingManager: RecordingManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 54),
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
        
        positionAtBottomCenter()
        
        // Sync visibility and active-window blue highlight with recording state
        recordingManager.$isRecording
            .combineLatest(recordingManager.$isProcessing, recordingManager.$isHandsFreeMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isProcessing, isHandsFreeMode in
                guard let self = self else { return }
                let isActive = isRecording || isProcessing || isHandsFreeMode
                
                if isActive {
                    self.showInteraction(isRecording: isRecording)
                } else {
                    self.hideInteraction()
                }
            }
            .store(in: &cancellables)
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func positionAtBottomCenter() {
        let screen = NSScreen.screens.first(where: { NSPointInRect(NSEvent.mouseLocation, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let x = screen.visibleFrame.midX - (targetWidth / 2)
        let y = screen.visibleFrame.minY + 44
        self.setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
    }
    
    private func showInteraction(isRecording: Bool) {
        positionAtBottomCenter()
        
        // 1. Show the Wispr Flow blue selection border around the active application window
        if isRecording {
            WindowHighlightOverlay.shared.show()
        }
        
        // 2. Animate the floating pill in at the bottom center
        guard self.alphaValue < 1.0 || !self.isVisible else { return }
        
        let currentOrigin = self.frame.origin
        // Start 10pt lower for a subtle upward entrance animation
        self.setFrameOrigin(NSPoint(x: currentOrigin.x, y: currentOrigin.y - 8))
        self.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
            self.animator().setFrameOrigin(currentOrigin)
        }
    }
    
    private func hideInteraction() {
        // 1. Fade out the active-window blue selection border
        WindowHighlightOverlay.shared.hide()
        
        // 2. Fade and slide down the bottom pill after brief confirmation
        guard self.isVisible, self.alphaValue > 0 else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self = self else { return }
            let destinationOrigin = NSPoint(x: self.frame.origin.x, y: self.frame.origin.y - 8)
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
                self.animator().setFrameOrigin(destinationOrigin)
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                if self.alphaValue == 0 {
                    self.orderOut(nil)
                }
            })
        }
    }
}
