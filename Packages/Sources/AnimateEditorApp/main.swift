import AppKit
import EditorShellFeature
import SwiftUI

/// Application entry point.
///
/// Composition only: it builds the window and hands it the root view. All
/// behaviour lives in the feature targets.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = "Animate Editor"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: AppRootView())
        window.center()
        // The editor layout has a floor below which its panels have nothing
        // left to show; enforce it rather than degrading past that point.
        window.contentMinSize = EditorShellView<EmptyView>.minimumWindowSize
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
