import AppKit
import Foundation
import SwiftUI

/// Reports horizontal scroll wheel and trackpad events.
///
/// SwiftUI offers no scroll-wheel hook on macOS, so this is an AppKit monitor
/// over the view's own frame. Worth the wrapper: panning a zoomed timeline by
/// two-finger scroll is what a hand reaches for before it thinks to hold a
/// modifier, and a timeline that can only be panned with a shortcut nobody was
/// shown may as well not pan at all.
struct ScrollPanModifier: ViewModifier {
    let onPan: (CGFloat) -> Void

    @State private var monitor: Any?
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            // Measured in the view's own space, and hit-tested by asking AppKit
            // what is under the pointer.
            //
            // Comparing frames by hand meant three coordinate systems at once:
            // SwiftUI's `.global` counts down from the top, an `NSEvent` reports
            // window coordinates counting up from the bottom, and a screen point
            // is neither. They never matched, so the monitor discarded every
            // scroll before it reached the timeline.
            // In front, not behind.
            //
            // As a background it sat under the lanes' own `ScrollView`, which
            // takes every wheel event before anything below it sees one —
            // measured, not a single event arrived. In front it is asked first,
            // and passes on what it does not want.
            .overlay(ScrollCatcher(onPan: onPan))
    }
}

/// An AppKit view that answers scroll events for the region it covers.
///
/// SwiftUI has no scroll-wheel hook on macOS, and a window-wide monitor cannot
/// tell whether the pointer is over one view or another without doing its own
/// hit-testing. A real view in the hierarchy is asked by AppKit itself.
private struct ScrollCatcher: NSViewRepresentable {
    let onPan: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCatchingView {
        let view = ScrollCatchingView()
        view.onPan = onPan
        return view
    }

    func updateNSView(_ view: ScrollCatchingView, context: Context) {
        view.onPan = onPan
    }
}

final class ScrollCatchingView: NSView {
    var onPan: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {

        // Horizontal where the device has one, vertical otherwise: a trackpad
        // and a Magic Mouse report sideways scrolling directly, while an
        // ordinary wheel has none — and a timeline is a horizontal thing, so
        // its one wheel should move it along.
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let delta = abs(dx) >= abs(dy) ? dx : dy

        // Horizontal is this view's business; vertical belongs to whatever
        // scrolls the lanes, so it is passed along untouched.
        // The hit test already established this is a sideways scroll.
        _ = dy
        guard let onPan else { return }
        onPan(dx)
    }

    // Transparent to the mouse, opaque to the wheel.
    //
    // Two mechanisms, and they have to be told apart. `hitTest` returning nil
    // makes the view invisible to *both* — measured, not one scroll arrived.
    // Forwarding `mouseDown` to `nextResponder` sends clicks *up* the
    // hierarchy, past the buttons sitting underneath, so the zoom controls
    // stopped answering.
    //
    // A view that is `hidden` is skipped by hit-testing entirely while still
    // receiving scroll events routed to the window, which is exactly the split
    // this needs.
    /// Invisible to clicks, present for the wheel.
    ///
    /// AppKit routes both through `hitTest`, so returning nil outright silenced
    /// the scroll as well — measured, not one event arrived. Returning nil only
    /// for the mouse keeps the two apart: the wheel arrives because the window
    /// asks this view directly in `scrollWheel`, and clicks fall through to the
    /// buttons underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .scrollWheel else { return nil }

        // Only sideways scrolling belongs here.
        //
        // Claiming every wheel event meant the lanes could not be scrolled
        // through at all: passing the vertical ones to `super` sends them *up*
        // the hierarchy, and the `ScrollView` that wanted them is underneath.
        // Refusing the hit test instead leaves them to whatever is below, which
        // is exactly where they were going.
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        return abs(dx) > abs(dy) && dx != 0 ? self : nil
    }

}

extension View {
    func onScrollPan(_ onPan: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollPanModifier(onPan: onPan))
    }
}
