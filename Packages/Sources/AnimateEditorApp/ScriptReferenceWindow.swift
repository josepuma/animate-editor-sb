import AppKit
import ScriptEditorFeature
import SwiftUI

/// The scripting reference, in a window of its own.
///
/// One window reused rather than a new one per click: a reference somebody
/// opens twice should come forward, not stack up behind itself.
///
/// A plain `NSWindow` rather than a SwiftUI `Window` scene, because this app
/// builds its main window that way too — `main.swift` does the same thing —
/// and mixing the two makes the window list depend on which came first.
@MainActor
enum ScriptReferenceWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        created.title = "Scripting Reference"
        created.contentView = NSHostingView(rootView: ScriptReferenceView())
        created.isReleasedWhenClosed = false
        created.center()
        created.makeKeyAndOrderFront(nil)

        window = created
    }
}
