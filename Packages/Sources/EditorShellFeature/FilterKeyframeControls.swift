import DesignSystem
import StoryboardCore
import SwiftUI

/// The stopwatch and diamond beside an animatable filter parameter.
///
/// Deliberately the same pair, in the same order, with the same glyphs as the
/// transform's row: a stopwatch has to mean one thing wherever it appears, and
/// somebody who has animated a clip's position already knows what these do.
///
/// Shown only where the *descriptor* says the parameter can be animated, so
/// this view never asks which filter it is looking at — a filter that makes a
/// parameter animatable needs no work here.
struct FilterKeyframeControls: View {
    /// The keyframes on this parameter, if any.
    let track: StoryboardCore.KeyframeTrack?
    /// Where the playhead is inside the clip, already clamped to it.
    let keyTime: Double
    /// What the parameter is worth right now, for the key a diamond plants.
    let current: Double
    /// What animating this costs, when it is not free.
    let costWarning: String?

    let beginAnimating: () -> Void
    let setEnabled: (Bool) -> Void
    let addKey: () -> Void
    let clear: () -> Void

    private var hasKeys: Bool { !(track?.isEmpty ?? true) }
    private var isAnimating: Bool { track?.isActive ?? false }

    private var isOnAKey: Bool {
        track?.keyframes.contains { abs($0.time - keyTime) < 1 } ?? false
    }

    private var stopwatchHelp: String {
        if !hasKeys { return costWarning ?? "Animate this" }
        return isAnimating ? "Switch animation off" : "Switch animation back on"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            IconButton(
                systemImage: isAnimating ? "stopwatch.fill" : "stopwatch",
                size: Theme.Size.controlTiny,
                isActive: isAnimating,
                help: stopwatchHelp,
            ) {
                if hasKeys {
                    setEnabled(!isAnimating)
                } else {
                    beginAnimating()
                }
            }

            // A key at the playhead, so the field is not the only way to plant
            // one. Hidden until animating, because before that there is nothing
            // for it to add to.
            if isAnimating {
                IconButton(
                    systemImage: isOnAKey ? "diamond.fill" : "diamond",
                    size: Theme.Size.controlTiny,
                    isActive: isOnAKey,
                    help: isOnAKey ? "On a keyframe" : "Add a keyframe here",
                    action: addKey,
                )
            }
        }
        .contextMenu {
            if hasKeys {
                Button(isAnimating ? "Disable Animation" : "Enable Animation") {
                    setEnabled(!isAnimating)
                }
                Divider()
                // Its own menu item rather than a second meaning for the
                // stopwatch: there is no undo to climb out of a delete with.
                Button("Delete All Keyframes", systemImage: "trash", role: .destructive) {
                    clear()
                }
            }
        }
    }
}
