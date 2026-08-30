import AppKit
import EditorShellFeature
import SwiftUI

/// Application entry point.
///
/// Composition only: it builds the window and hands it the root view. All
/// behaviour lives in the feature targets.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?

    /// Keeps the title bar out of full screen entirely.
    ///
    /// Hiding the toolbar from SwiftUI is not enough on its own: in full screen
    /// macOS slides the whole bar back in whenever the pointer nears the top of
    /// the screen. Dropping it from the presentation is what stops that — the
    /// mode exists to leave nothing but the picture.
    nonisolated func window(
        _: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions,
    ) -> NSApplication.PresentationOptions {
        proposedOptions.union([.autoHideToolbar, .autoHideMenuBar, .fullScreen])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        // The title stays set for the Window menu and the Dock, but is not
        // drawn: the editor's own header already names what is open, and a
        // second name above it costs a band of window to say nothing.
        window.title = "Animate Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: AppRootView())
        window.center()
        // The editor layout has a floor below which its panels have nothing
        // left to show; enforce it rather than degrading past that point.
        window.contentMinSize = EditorShellView<EmptyView>.minimumWindowSize
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
application.appearance = NSAppearance(named: .darkAqua)
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
