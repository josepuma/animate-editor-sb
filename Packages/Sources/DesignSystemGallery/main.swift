import AppKit
import SwiftUI

/// A catalogue of the design system, as its own window.
///
/// Two controls that disagree are invisible while each is only ever seen in its
/// own corner of the app. Side by side, a stray radius or a font one step off
/// is obvious at a glance.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// The system is dark-only, and the gallery has to show what ships.
app.appearance = NSAppearance(named: .darkAqua)

let delegate = GalleryAppDelegate()
app.delegate = delegate
app.run()

@MainActor
final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = "Design System"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: GalleryView())
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
