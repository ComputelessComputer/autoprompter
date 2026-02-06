import AppKit
import Combine
import SwiftUI

@main
struct AutoprompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var opacitySink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let viewModel = TeleprompterViewModel()
        let contentView = ContentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        // Visual‑effect view for the frosted‑glass background.
        // .underWindowBackground is the lightest/least‑tinted material.
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .none
        window.isOpaque = false
        window.backgroundColor = .clear

        // Stack: visual‑effect background → SwiftUI hosting view.
        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]
        visualEffect.frame = container.bounds
        container.addSubview(visualEffect)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        window.contentView = container

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Bind the slider value to window alpha for real translucency.
        opacitySink = viewModel.$windowOpacity
            .receive(on: RunLoop.main)
            .sink { [weak window] value in
                window?.alphaValue = CGFloat(value)
            }

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
