import AppKit
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
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory so there's no dock icon; the notch panel is the UI.
        NSApp.setActivationPolicy(.accessory)

        let viewModel = TeleprompterViewModel()
        let controller = NotchWindowController()
        controller.setup(viewModel: viewModel)
        self.notchController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
