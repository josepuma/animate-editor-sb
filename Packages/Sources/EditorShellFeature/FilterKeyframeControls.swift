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
    /// Moves the playhead to a moment in the clip, for the arrows either side
    /// of the diamond.
    var goToTime: (Double) -> Void = { _ in }

    private var hasKeys: Bool { !(track?.isEmpty ?? true) }
    private var isAnimating: Bool { track?.isActive ?? false }

    private var isOnAKey: Bool {
        track?.keyframes.contains { abs($0.time - keyTime) < 1 } ?? false
    }

    /// Strictly before and after, by the same tolerance the diamond uses to
    /// call itself filled — standing on a key must not offer to jump to itself.
    private var previousKey: StoryboardCore.Keyframe? {
        track?.keyframes.last { $0.time < keyTime - 1 }
    }

    private var nextKey: StoryboardCore.Keyframe? {
        track?.keyframes.first { $0.time > keyTime + 1 }
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
            // one — with an arrow either side to reach the neighbouring keys.
            // The same arrangement the timeline rows use, and After Effects
            // before them: navigation sits either side of the thing it moves
            // between.
            //
            // Hidden until animating, because before that there is nothing for
            // them to add to or move between.
            if isAnimating {
                IconButton(
                    systemImage: "arrowtriangle.left.fill",
                    size: Theme.Size.controlTiny,
                    help: previousKey == nil
                        ? "No earlier keyframe"
                        : "Go to previous keyframe",
                ) {
                    previousKey.map { goToTime($0.time) }
                }
                // Dimmed rather than hidden at the ends: a control that
                // disappears shifts the diamond under the pointer, so the next
                // click lands on something else.
                .disabled(previousKey == nil)
                .opacity(previousKey == nil ? 0.35 : 1)

                IconButton(
                    systemImage: isOnAKey ? "diamond.fill" : "diamond",
                    size: Theme.Size.controlTiny,
                    isActive: isOnAKey,
                    help: isOnAKey ? "On a keyframe" : "Add a keyframe here",
                    action: addKey,
                )

                IconButton(
                    systemImage: "arrowtriangle.right.fill",
                    size: Theme.Size.controlTiny,
                    help: nextKey == nil ? "No later keyframe" : "Go to next keyframe",
                ) {
                    nextKey.map { goToTime($0.time) }
                }
                .disabled(nextKey == nil)
                .opacity(nextKey == nil ? 0.35 : 1)
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
