import AppKit
import DesignSystem
import EditorShellFeature
import StoryboardCore
import StoryboardRendering
import StoryboardScripting
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
        // Text needs a font to measure against and a place to draw glyphs, and
        // neither can live in Core. Installed once, before anything evaluates.
        TextTextures.install()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        // The title stays set for the Window menu and the Dock, but is not
        // drawn: the editor's own header already names what is open, and a
        // second name above it costs a band of window to say nothing.
        window.title = "Pulse Studio"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The window's own tone, so the transparent title bar shows the same
        // surface as the content under it. Left undeclared it is AppKit's
        // default grey, and the band above the editor read as a seam.
        window.backgroundColor = NSColor(Theme.Tone.base)
        window.contentView = NSHostingView(rootView: AppRootView())
        window.center()
        // The editor layout has a floor below which its panels have nothing
        // left to show; enforce it rather than degrading past that point.
        window.contentMinSize = EditorShellView<EmptyView>.minimumWindowSize
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        // Nothing starts focused. AppKit hands first responder to the first
        // text field it finds, and an inspector full of them means the editor
        // opens with a parameter quietly holding the keyboard — space, which
        // is play/pause, goes into that field as a character instead.
        window.makeFirstResponder(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
application.appearance = NSAppearance(named: .darkAqua)

// Before any view: an unregistered face falls back to the system font without
// a word, which is a typeface bug nobody would notice was one.
Theme.registerFonts()
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
// A bare SwiftPM executable has no bundle and so no icon of its own: without
// this the Dock shows the generic executable glyph. It only lasts while the app
// runs — Finder's icon needs a real `.app` bundle.
if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
   let icon = NSImage(contentsOf: iconURL) {
    application.applicationIconImage = icon
}
application.run()
