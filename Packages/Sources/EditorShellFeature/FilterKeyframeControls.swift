import DesignSystem
import StoryboardCore
import SwiftUI

/// The stopwatch and keyframe navigation of an animatable filter parameter.
///
/// Deliberately the same controls, in the same places, with the same glyphs as
/// the transform's row: a stopwatch has to mean one thing wherever it appears,
/// and somebody who has animated a clip's position already knows what these
/// do.
///
/// Two pieces rather than one view, because they live in two columns of the
/// row — the stopwatch before the label, the navigation after the field — the
/// way `TransformRow` lays them out. As one view after the field, a parameter
/// row and a transform row put the same stopwatch in different places.
///
/// Shown only where the *descriptor* says the parameter can be animated, so
/// this never asks which filter it is looking at — a filter that makes a
/// parameter animatable needs no work here.
///
/// `@MainActor` by hand: as a `View` it inherited the main actor from the
/// protocol, and as a plain struct that builds views it has to say so — the
/// views it makes are main-actor types, and Swift 6 will not let a nonisolated
/// value hand them its closures.
@MainActor
struct FilterKeyframeControls {
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

    /// Before the label.
    var stopwatch: some View {
        IconButton(
            systemImage: isAnimating ? "stopwatch.fill" : "stopwatch",
            size: Theme.Size.controlTiny,
            isActive: isAnimating,
            tint: Theme.Palette.accent,
            help: stopwatchHelp,
        ) {
            if hasKeys {
                setEnabled(!isAnimating)
            } else {
                beginAnimating()
            }
        }
        .contextMenu { menu }
    }

    /// After the field. Draws nothing until animating — before that there is
    /// nothing to add to or move between — while the panel's grid keeps its
    /// column. Previous and next key are on its menu.
    var navigator: some View {
        KeyframeDiamond(
            isAnimating: isAnimating,
            isOnKey: isOnAKey,
            addKey: addKey,
            previous: previousKey.map { key in { goToTime(key.time) } },
            next: nextKey.map { key in { goToTime(key.time) } },
        )
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
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
