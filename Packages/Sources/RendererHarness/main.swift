import AppKit
import PlaybackFeature
import SwiftUI

/// Development harness for the Metal renderer.
///
/// Feeds the playback feature a generated storyboard so rendering work needs no
/// beatmap folder on disk. Run with `swift run RendererHarness`.
@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let source = InMemoryStoryboardSource(
            displayName: "Demo storyboard",
            osb: DemoStoryboard.make(),
            images: { DemoTextures.png(for: $0) },
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = "Renderer Harness"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(
            rootView: PlaybackView(
                model: PlaybackModel(),
                timeline: TimelineModel(),
                source: source,
            ),
        )
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
let delegate = HarnessAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
