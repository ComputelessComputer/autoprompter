import AppKit
import Combine
import SwiftUI

// MARK: - Custom panel that doesn't steal focus

/// NSPanel subclass that refuses key/main status so it never steals
/// focus from whatever app the user is presenting in.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Window controller

/// Manages a borderless panel that sits at the top of the screen,
/// visually extending from the MacBook notch.
@MainActor
final class NotchWindowController {

    private var panel: NotchPanel?
    private var stateSink: AnyCancellable?

    private let wingWidth: CGFloat = 200
    private let collapsedHeight: CGFloat = 34
    private let peekContentHeight: CGFloat = 110
    private let semiExpandedContentHeight: CGFloat = 300
    private let fullExpandedContentHeight: CGFloat = 480

    func setup(viewModel: TeleprompterViewModel) {
        guard let screen = NSScreen.main else { return }

        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : collapsedHeight
        let notchWidth = estimateNotchWidth(screen: screen)
        let panelWidth = notchWidth + wingWidth * 2

        let screenFrame = screen.frame
        let panelX = screenFrame.midX - panelWidth / 2

        let initialHeight = notchHeight
        let panelY = screenFrame.maxY - initialHeight
        let initialFrame = NSRect(x: panelX, y: panelY, width: panelWidth, height: initialHeight)

        let panel = NotchPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true

        let contentView = NotchContentView(viewModel: viewModel, notchWidth: notchWidth, notchHeight: notchHeight)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: initialFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel

        stateSink = viewModel.$isExpanded
            .combineLatest(viewModel.$isRunning, viewModel.$isHovering)
            .receive(on: RunLoop.main)
            .sink { [weak self] isExpanded, isRunning, isHovering in
                guard let self else { return }
                let contentHeight: CGFloat
                if !isRunning && !isExpanded {
                    contentHeight = 0
                } else if !isRunning {
                    contentHeight = self.fullExpandedContentHeight
                } else if !isHovering {
                    contentHeight = self.peekContentHeight
                } else {
                    contentHeight = self.semiExpandedContentHeight
                }
                self.animateToHeight(notchHeight + contentHeight, screen: screen)
            }


    }

    // MARK: - Animation

    private func animateToHeight(_ targetHeight: CGFloat, screen: NSScreen) {
        guard let panel else { return }
        let screenFrame = screen.frame
        let targetY = screenFrame.maxY - targetHeight
        let targetFrame = NSRect(x: panel.frame.origin.x, y: targetY,
                                  width: panel.frame.width, height: targetHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Notch geometry

    private func estimateNotchWidth(screen: NSScreen) -> CGFloat {
        if #available(macOS 14.0, *) {
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea,
               leftArea != .zero, rightArea != .zero {
                let notchW = screen.frame.width - leftArea.width - rightArea.width
                if notchW > 50 && notchW < 400 { return notchW }
            }
        }
        if screen.safeAreaInsets.top > 0 { return 200 }
        return 0
    }
}
