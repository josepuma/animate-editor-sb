import AppKit
import Foundation

/// Hands a script file to an editor.
///
/// Three steps down, because the author's setup is not this app's to assume.
/// VSCode first, since that is what the scripting workflow is written around;
/// then whatever the system opens a `.js` with, which is the honest answer for
/// someone who uses a different editor; then Finder, which at least puts the
/// file in front of them.
///
/// The last step matters more than it looks: a click that silently does
/// nothing leaves the author unable to tell a broken app from a missing
/// editor.
enum ScriptLauncher {
    /// Bundle identifiers to try, in order.
    ///
    /// Insiders as well as the stable build: someone running Insiders has no
    /// stable VSCode installed, and falling through to "whatever opens a
    /// `.js`" would hand their script to Xcode.
    static let preferredEditors = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
    ]

    /// Opens `file`, returning whether anything took it.
    @MainActor
    static func open(_ file: URL) -> Bool {
        if let editor = preferredEditor(), openFile(file, with: editor) {
            return true
        }
        // Whatever the system associates with a `.js`. Returns false when
        // nothing is associated, which is why Finder is below it rather than
        // being the only fallback.
        if NSWorkspace.shared.open(file) {
            return true
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
        return true
    }

    /// The first preferred editor that is actually installed.
    private static func preferredEditor() -> URL? {
        for identifier in preferredEditors {
            if let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: identifier)
            {
                return url
            }
        }
        return nil
    }

    /// Opens `file` with a specific application.
    ///
    /// Asynchronous by API, so the return value says the request was made
    /// rather than that a window appeared — which is all a caller can know
    /// about another process anyway.
    @MainActor
    private static func openFile(_ file: URL, with application: URL) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([file], withApplicationAt: application, configuration: configuration)
        return true
    }
}
