import AppKit
import SwiftUI

/// Hands the keyboard back when a click lands anywhere but a text field.
///
/// Fields commit what was typed when they lose focus, so this is what makes a
/// click elsewhere keep the value — without it a number was only saved by
/// pressing Return, and clicking away quietly discarded nothing but also
/// applied nothing.
///
/// A window-wide monitor rather than a background view: a background only
/// answers the gaps between controls, and most of an editor is controls. The
/// panels, the timeline and the canvas all swallow their own clicks, so a
/// backdrop never sees them.
struct FocusReleaseModifier: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    releaseIfNeeded(for: event)
                    // Passed on untouched: this only observes, so whatever was
                    // clicked still receives its click.
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func releaseIfNeeded(for event: NSEvent) {
        guard let window = event.window,
              let responder = window.firstResponder as? NSText,
              responder.isEditable
        else { return }

        // The field editor is a shared view that moves between fields, so the
        // thing to ask about is its delegate — the field it is currently
        // serving. A click inside that field is someone still editing.
        let editing = (responder.delegate as? NSView) ?? responder
        let point = editing.convert(event.locationInWindow, from: nil)
        guard !editing.bounds.contains(point) else { return }

        // Ends editing rather than discarding it: `makeFirstResponder(nil)`
        // makes the field resign, which is what SwiftUI reports as focus lost
        // and what commits the value.
        window.makeFirstResponder(nil)
    }
}

extension View {
    /// Commits and dismisses an edit when a click lands outside its field.
    func releasesFocusOnOutsideClick() -> some View {
        modifier(FocusReleaseModifier())
    }
}
