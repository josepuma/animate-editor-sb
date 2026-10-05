import DesignSystem
import SwiftUI

/// One effect already on the timeline.
package struct PlacedEffectRow: View {
    private let name: String
    /// The colour of the layer it draws on.
    private let tint: Color
    private let isVisible: Bool
    private let isSelected: Bool
    private let select: () -> Void
    private let remove: () -> Void

    @State private var isHovered = false

    package init(
        name: String,
        tint: Color,
        isVisible: Bool,
        isSelected: Bool,
        select: @escaping () -> Void,
        remove: @escaping () -> Void,
    ) {
        self.name = name
        self.tint = tint
        self.isVisible = isVisible
        self.isSelected = isSelected
        self.select = select
        self.remove = remove
    }

    package var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // A short bar of the layer's colour — the same pill that marks the
            // active tab, so a coloured edge reads as "belongs to" everywhere.
            Capsule()
                .fill(tint.opacity(isVisible ? 1 : 0.35))
                .frame(width: Theme.Size.indicator, height: Theme.Size.indicatorLength)

            Text(name)
                .font(Theme.Typography.label)
                .foregroundStyle(isVisible ? Theme.Palette.primary : Theme.Palette.tertiary)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.tight)

            // Revealed on hover: a delete button on every row turns a list into
            // a row of buttons, and the one that matters is the row itself.
            if isHovered {
                IconButton(
                    systemImage: "trash",
                    size: Theme.Size.controlTiny,
                    help: "Remove \(name)",
                    action: remove,
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.control)
        .rowSurface(isSelected: isSelected, isHovered: isHovered)
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isSelected)
    }
}
