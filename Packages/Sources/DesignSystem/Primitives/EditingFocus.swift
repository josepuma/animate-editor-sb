import AppKit

/// Whether the keyboard currently belongs to a text field.
///
/// A shortcut is claimed at window level, so one that fires while somebody is
/// typing does something much larger than what was asked: ⌘Z undoes the last
/// document edit instead of the last keystroke, and the space bar plays the
/// track instead of separating two words.
///
/// It lives here rather than in a feature because two features need it — the
/// shell gates its editing commands on it, and the canvas has to gate the space
/// bar — and features never import each other. It is also not a fact about
/// storyboards: it is a fact about AppKit's first responder, which is exactly
/// the kind of thing the design system already holds.
@MainActor
public enum EditingFocus {
    /// Whether the key window's first responder is taking typed input.
    ///
    /// `NSApp` is force-unwrapped by its own declaration but is genuinely nil
    /// with no `NSApplication` running — which crashed on the first test that
    /// asked. It lived in a view before, where an app always exists; a utility
    /// cannot assume one, and the honest answer without a window is "nothing is
    /// being edited". Reported the other way, every shortcut in the app would
    /// go dead.
    public static var isActive: Bool {
        guard let app = NSApp else { return false }
        return isEditing(app.keyWindow?.firstResponder)
    }

    /// Whether `responder` is taking typed input.
    ///
    /// Split out so it can be tested against a responder built by hand: the
    /// property above depends on which window the system considers key, which a
    /// test cannot arrange reliably.
    ///
    /// A focused `NSTextField` hands the keyboard to a shared field editor, so
    /// the responder is an `NSText` whose delegate is the field — which is why
    /// this checks for the editor rather than for the field itself. A code
    /// editor is an `NSTextView`, checked separately.
    public static func isEditing(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if let text = responder as? NSText { return text.isEditable }
        return responder is NSTextView
    }
}
