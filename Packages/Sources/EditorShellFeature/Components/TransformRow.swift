import DesignSystem
import SwiftUI

/// One animatable property: its value here and now, and a switch for animating.
///
/// The stopwatch is After Effects' idea and it is the right one — a property is
/// a number until you say otherwise, and saying otherwise is one click. Before
/// that there are no keys to manage and no row to read.
package struct TransformRow: View {
    /// What the row edits, as the four facts it needs about it.
    ///
    /// Not a `TransformProperty`, which is all it ever read one for: taking
    /// the facts lets the camera's pan and zoom use the same row — one
    /// stopwatch, one meaning, everywhere in the app.
    private let title: String
    private let unit: String?
    private let step: Double
    private let range: ClosedRange<Double>
    /// The times of the property's keys, in the clip's own clock.
    ///
    /// Not the track itself: all the row ever asked of it was how many keys
    /// there are and whether one sits at the playhead.
    private let keyTimes: [Double]
    /// Whether the animation is switched on, as opposed to merely having keys.
    private let isAnimating: Bool
    /// What the property is worth right now — its resting value, or its
    /// animation sampled at the playhead.
    private let current: Double
    /// Where the playhead is inside the clip.
    private let localTime: Double
    private let duration: Double
    private let setValue: (Double, Double) -> Void
    private let beginAnimating: (Double) -> Void
    private let setEnabled: (Bool, Double) -> Void
    private let clear: (Double) -> Void
    /// Moves the playhead to a key, in the row's own clock. Without it the
    /// diamond's previous and next items stay disabled.
    private let goToTime: ((Double) -> Void)?

    package init(
        title: String,
        unit: String?,
        step: Double,
        range: ClosedRange<Double>,
        keyTimes: [Double],
        isAnimating: Bool,
        current: Double,
        localTime: Double,
        duration: Double,
        setValue: @escaping (Double, Double) -> Void,
        beginAnimating: @escaping (Double) -> Void,
        setEnabled: @escaping (Bool, Double) -> Void,
        clear: @escaping (Double) -> Void,
        goToTime: ((Double) -> Void)? = nil,
    ) {
        self.title = title
        self.unit = unit
        self.step = step
        self.range = range
        self.keyTimes = keyTimes
        self.isAnimating = isAnimating
        self.current = current
        self.localTime = localTime
        self.duration = duration
        self.setValue = setValue
        self.beginAnimating = beginAnimating
        self.setEnabled = setEnabled
        self.clear = clear
        self.goToTime = goToTime
    }

    private var hasKeys: Bool { !keyTimes.isEmpty }

    /// Where a new key would land, clamped into the clip.
    private var keyTime: Double { max(0, min(localTime, duration)) }

    /// Whether there is a key at the playhead right now.
    private var isOnAKey: Bool {
        keyTimes.contains { abs($0 - keyTime) < 1 }
    }

    /// Strictly before and after, by the same tolerance the diamond uses to
    /// call itself filled — standing on a key must not offer to jump to itself.
    private var previousKey: Double? { keyTimes.last { $0 < keyTime - 1 } }
    private var nextKey: Double? { keyTimes.first { $0 > keyTime + 1 } }

    package var body: some View {
        PropertyRow(title) {
            // Before the label, After Effects' place for it: the switch that
            // decides whether the property is a number or an animation reads
            // first, and the right-hand side stays for the value.
            IconButton(
                systemImage: isAnimating ? "stopwatch.fill" : "stopwatch",
                size: Theme.Size.controlTiny,
                isActive: isAnimating,
                tint: Theme.Palette.accent,
                help: stopwatchHelp,
            ) {
                // The stopwatch starts animating, and afterwards switches the
                // animation on and off *without* discarding it. Deleting a
                // stopwatch's worth of work on the same click that started it
                // is a trap, and there is no undo to climb out of it with.
                if hasKeys {
                    setEnabled(!isAnimating, keyTime)
                } else {
                    beginAnimating(keyTime)
                }
            }
        } control: {
            NumberField(
                value: Binding(
                    get: { current },
                    // Typing while animating sets a key at the playhead —
                    // the same move as dragging a property in any editor
                    // with a timeline. Otherwise it sets the value.
                    set: { setValue($0, keyTime) },
                ),
                unit: unit,
                step: step,
                range: range,
                format: step < 1 ? "%.2f" : "%.0f",
            )
        } trailing: {
            KeyframeDiamond(
                isAnimating: isAnimating,
                isOnKey: isOnAKey,
                // A key at the playhead, so the timeline is not the only place
                // one can be added.
                addKey: { setValue(current, keyTime) },
                previous: goToTime.flatMap { go in previousKey.map { key in { go(key) } } },
                next: goToTime.flatMap { go in nextKey.map { key in { go(key) } } },
            )
        }
        .contextMenu {
            if hasKeys {
                Button(isAnimating ? "Disable Animation" : "Enable Animation") {
                    setEnabled(!isAnimating, keyTime)
                }
                Divider()
                // Destructive, so it is a deliberate menu item rather than a
                // side effect of the switch beside the field.
                Button("Delete All Keyframes", systemImage: "trash", role: .destructive) {
                    clear(keyTime)
                }
            }
        }
    }

    /// The key count lives here now. It was a badge after the field, which
    /// competed with the value for the eye; the keys themselves are on the
    /// timeline, and the number is a detail for whoever asks.
    private var stopwatchHelp: String {
        if !hasKeys { return "Animate \(title)" }
        let keys = keyTimes.count == 1 ? "1 keyframe" : "\(keyTimes.count) keyframes"
        return isAnimating
            ? "\(keys) — switch off \(title) animation (keys are kept)"
            : "\(keys), switched off — switch \(title) animation back on"
    }
}
