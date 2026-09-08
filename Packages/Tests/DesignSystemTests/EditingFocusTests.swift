import AppKit
import Testing

@testable import DesignSystem

/// Whether the keyboard currently belongs to a text field.
///
/// It lives in the design system rather than in a feature because two features
/// need it — the shell gates ⌘Z and friends on it, and the canvas has to gate
/// the space bar — and features never import each other. It is also not a fact
/// about storyboards: it is a fact about AppKit's first responder.
@Suite("Editing focus")
@MainActor
struct EditingFocusTests {
    /// With no window, nothing is being edited.
    ///
    /// The honest answer for a headless test run, and the safe one: reported as
    /// editing, every shortcut in the app would go dead.
    @Test("no key window means nothing is being edited")
    func noWindowIsNotEditing() {
        #expect(EditingFocus.isActive == false)
    }

    /// An `NSTextView` counts.
    ///
    /// This is the case the code editor depends on, and the reason the check
    /// cannot simply look for `NSTextField`: the editor is a text *view*, and a
    /// gate that misses it would let the space bar reach play/pause instead of
    /// the file being typed into.
    ///
    /// Tested against the responder directly rather than by focusing one in a
    /// real window. The first version built an `NSWindow` and called
    /// `makeKeyAndOrderFront`, which **hangs** with no `NSApplication` running
    /// — so it would hang the suite locally and on a CI runner, where there is
    /// no app either. What matters here is the classification, and that needs
    /// no window.
    @Test("a text view is editing")
    func textViewIsEditing() {
        #expect(EditingFocus.isEditing(NSTextView(frame: .zero)))
    }

    /// A read-only text view does not count.
    ///
    /// A label rendered as text should not swallow shortcuts — nobody is typing
    /// into it, so there is nothing to protect.
    @Test("a read-only text field editor is not editing")
    func readOnlyIsNotEditing() {
        let text = NSText(frame: .zero)
        text.isEditable = false

        #expect(EditingFocus.isEditing(text) == false)
    }

    @Test("an ordinary view is not editing")
    func plainViewIsNotEditing() {
        #expect(EditingFocus.isEditing(NSView(frame: .zero)) == false)
        #expect(EditingFocus.isEditing(nil) == false)
    }
}
