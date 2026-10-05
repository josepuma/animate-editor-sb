import DesignSystem
import SwiftUI

/// The effect itself: expands its presets, or places a blank one.
package struct EffectHeaderRow: View {
    private let name: String
    private let systemImage: String
    /// `nil` when the effect has no presets, which is what turns the row from a
    /// disclosure into a plain "add this".
    private let presetCount: Int?
    private let isExpanded: Bool
    private let toggleExpanded: () -> Void
    private let add: () -> Void
    /// The tile's colour. `nil` keeps it neutral.
    private let tint: Color?

    @State private var isHovered = false

    package init(
        name: String,
        systemImage: String,
        presetCount: Int?,
        isExpanded: Bool,
        toggleExpanded: @escaping () -> Void,
        add: @escaping () -> Void,
        tint: Color? = nil,
    ) {
        self.name = name
        self.systemImage = systemImage
        self.presetCount = presetCount
        self.isExpanded = isExpanded
        self.toggleExpanded = toggleExpanded
        self.add = add
        self.tint = tint
    }

    package var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // The space is kept either way, so the tiles of every row line up
            // whether or not it discloses anything.
            Image(systemName: "chevron.right")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(presetCount == nil ? 0 : 1)
                .frame(width: Theme.Spacing.compact)

            GlyphTile(systemImage: systemImage, tint: tint, size: Theme.Size.controlSmall)

            Text(name)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.primary)

            Spacer(minLength: Theme.Spacing.tight)

            if let presetCount {
                CountBadge(presetCount)
                    .help("\(presetCount) presets")
            }

            // Placing a blank effect stays available beside the presets: it is
            // the one anybody building something of their own reaches for.
            Button(action: add) {
                AddBadge(isHighlighted: isHovered)
            }
            .buttonStyle(.plain)
            .help(presetCount == nil ? "Add \(name)" : "Add a blank \(name)")
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.controlLarge)
        // Raised even at rest: an effect is a heading over its presets, and a
        // heading that only appears under the pointer is a heading nobody
        // can scan for.
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .fill(isHovered ? Theme.Tone.well : Theme.Tone.raised)
        }
        .contentShape(.rect)
        .onTapGesture(perform: toggleExpanded)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isExpanded)
    }
}
