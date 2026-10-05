import DesignSystem
import SwiftUI

/// One filter available to apply, draggable onto a track.
///
/// Dragged rather than only clicked because that is what the hand does with a
/// library — After Effects, Premiere and Resolve all work this way, and a panel
/// of things you can only click reads as a menu rather than as a shelf.
package struct FilterLibraryRow: View {
    private let name: String
    private let systemImage: String
    /// The filter's own type, which is what a drag carries so a drop can tell a
    /// filter from anything else that might be dragged over a lane.
    private let filterType: String
    /// Whether there is a lane to apply to. Clicking applies to the selection;
    /// with nothing selected there is nowhere for it to go.
    private let canApply: Bool
    private let apply: () -> Void

    @State private var isHovered = false

    package init(
        name: String,
        systemImage: String,
        filterType: String,
        canApply: Bool,
        apply: @escaping () -> Void,
    ) {
        self.name = name
        self.systemImage = systemImage
        self.filterType = filterType
        self.canApply = canApply
        self.apply = apply
    }

    package var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // Indented past where the heading's chevron sits, so a row reads as
            // belonging to the group above it rather than as a sibling of it.
            // The width matches the chevron's exactly: eyeballing the gap is
            // how a list ends up almost aligned, which is worse than not.
            Color.clear.frame(width: Theme.Spacing.compact, height: 0)

            // Filters share one colour — the keyframe palette's filter family —
            // so a filter reads as a filter in the library, on a clip and in
            // the keyframe editor alike.
            GlyphTile(systemImage: systemImage, tint: Theme.KeyframePalette.filter, size: Theme.Size.controlTiny)

            // No category subtitle: the heading above already says it, and a
            // row repeating its own group costs twice the height to say nothing
            // new. The same redundancy the pack rows had.
            Text(name)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.primary)

            Spacer(minLength: Theme.Spacing.tight)

            Image(systemName: "line.3.horizontal")
                .font(Theme.Typography.micro)
                .foregroundStyle(isHovered ? Theme.Palette.secondary : Theme.Palette.tertiary)
        }
        // The heading's padding, so the two line up down the left edge.
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.control)
        .rowSurface(isHovered: isHovered)
        .contentShape(.rect)
        .onTapGesture { if canApply { apply() } }
        .onHover { isHovered = $0 }
        // The type carried is the filter's own, so a drop can tell a filter
        // from anything else that might be dragged over a lane.
        .draggable(FilterTransfer(type: filterType).payload) {
            Label(name, systemImage: systemImage)
                .font(Theme.Typography.label)
                .padding(Theme.Spacing.snug)
                .background(.thinMaterial, in: Capsule())
        }
        .help(canApply
            ? "Drag onto a clip, or click to apply to the selected one"
            : "Drag onto a clip")
        .animation(Theme.Motion.quick, value: isHovered)
    }
}
