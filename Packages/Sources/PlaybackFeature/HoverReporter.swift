import AppKit
import SwiftUI

/// Reports when the pointer is inside its bounds.
///
/// SwiftUI's `onHover` is not enough over a Metal canvas: an `MTKView` handles
/// its own mouse tracking and does not pass those events up, so a SwiftUI view
/// wrapping one never hears about them.
///
/// A tracking area also covers the whole region at once, including the controls
/// drawn over it. Tracking each piece separately means the pointer "leaves" the
/// canvas the instant it crosses onto a button — hiding the controls exactly
/// when they are being reached for.
struct HoverReporter: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context _: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context _: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void = { _ in }

        private var trackingAreaForHover: NSTrackingArea?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // A view moved between windows carries no crossing event with it.
            syncWithPointer()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingAreaForHover {
                removeTrackingArea(trackingAreaForHover)
            }

            // `.activeInKeyWindow` rather than `.activeAlways`: a background
            // window revealing its controls under a passing pointer is noise.
            //
            // `.assumeInside` so a pointer already inside when the area is
            // installed is not counted as entering — otherwise a layout pass
            // under a resting pointer would latch the state on.
            let area = NSTrackingArea(
                rect: bounds,
                options: [
                    .mouseEnteredAndExited,
                    .activeInKeyWindow,
                    .inVisibleRect,
                    .assumeInside,
                ],
                owner: self,
            )
            addTrackingArea(area)
            trackingAreaForHover = area

            // The area only reports crossings, so a pointer that was already
            // inside — or has since left while the view was rebuilt — has to be
            // resolved directly.
            syncWithPointer()
        }

        /// Sets the state from where the pointer actually is.
        private func syncWithPointer() {
            guard let window else {
                onChange(false)
                return
            }

            let pointInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            onChange(window.isKeyWindow && bounds.contains(pointInView))
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onChange(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onChange(false)
        }
    }
}
