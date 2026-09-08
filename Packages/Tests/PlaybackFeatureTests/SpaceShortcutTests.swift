import AppKit
import DesignSystem
import Testing

@testable import PlaybackFeature

/// The space bar plays and pauses — except while somebody is typing.
///
/// It was claimed at window level with no such guard, unlike every ⌘ shortcut
/// in the shell. A one-line field survives that: the space bar reaches
/// play/pause instead of the field, which is wrong but survivable. A code
/// editor does not, because space is the most-typed character in code.
@Suite("Space shortcut")
@MainActor
struct SpaceShortcutTests {
    /// The gate the shortcut has to consult.
    ///
    /// Asserted through `EditingFocus` rather than by driving a real key event:
    /// a SwiftUI `keyboardShortcut` cannot be fired from a unit test, so what
    /// is testable is that the decision is delegated to the one place that
    /// knows — and that place is now shared with the shell rather than being a
    /// second copy.
    @Test("a text view holds the keyboard")
    func textViewHoldsTheKeyboard() {
        #expect(EditingFocus.isEditing(NSTextView(frame: .zero)))
    }

    @Test("an ordinary view does not")
    func plainViewDoesNot() {
        #expect(EditingFocus.isEditing(NSView(frame: .zero)) == false)
    }

    /// The transport's own guard, which is what the shortcut calls.
    @Test("the transport refuses to toggle while a field has focus")
    func transportRefusesWhileEditing() {
        #expect(CanvasOverlayControls.shouldToggleOnSpace(whileEditing: true) == false)
        #expect(CanvasOverlayControls.shouldToggleOnSpace(whileEditing: false))
    }
}
