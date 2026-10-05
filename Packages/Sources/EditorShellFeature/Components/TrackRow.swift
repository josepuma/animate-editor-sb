import DesignSystem
import SwiftUI

/// One lane in the Layers panel: its colour, name, effect count, and the eye and
/// lock switches.
package struct TrackRow: View {
    private let name: String
    private let tint: Color
    private let effectCount: Int
    private let isVisible: Bool
    private let isLocked: Bool
    private let isSelected: Bool
    private let select: () -> Void
    private let toggleVisibility: () -> Void
    private let toggleLock: () -> Void

    @State private var isHovered = false

    package init(
        name: String,
        tint: Color,
        effectCount: Int,
        isVisible: Bool,
        isLocked: Bool,
        isSelected: Bool,
        select: @escaping () -> Void,
        toggleVisibility: @escaping () -> Void,
        toggleLock: @escaping () -> Void,
    ) {
        self.name = name
        self.tint = tint
        self.effectCount = effectCount
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isSelected = isSelected
        self.select = select
        self.toggleVisibility = toggleVisibility
        self.toggleLock = toggleLock
    }

    package var body: some View {
        HStack(spacing: Theme.Spacing.compact) {
            // The lane's picture: its colour as a tile with its initial, not a
            // dot. A dot says "this has a colour"; a tile says "this is a
            // thing", which is what a layer is.
            GlyphTile(initialOf: name, tint: tint, size: Theme.Size.controlSmall)
                .opacity(isVisible ? 1 : 0.35)

            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Text(name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isVisible ? Theme.Palette.primary : Theme.Palette.tertiary)
                    .lineLimit(1)

                Text(effectCount == 1 ? "1 effect" : "\(effectCount) effects")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }

            Spacer(minLength: Theme.Spacing.tight)

            // Plain, not filled: the glyph dimming is the state. A filled
            // plate behind each switch made every row a pair of buttons with
            // a name attached.
            IconButton(
                systemImage: isVisible ? "eye" : "eye.slash",
                size: Theme.Size.controlTiny,
                isActive: isVisible,
                help: isVisible ? "Hide" : "Show",
                action: toggleVisibility,
            )

            IconButton(
                systemImage: isLocked ? "lock.fill" : "lock.open",
                size: Theme.Size.controlTiny,
                isActive: isLocked,
                tint: isLocked ? Theme.Palette.warning : nil,
                help: isLocked ? "Unlock" : "Lock",
                action: toggleLock,
            )
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.controlLarge)
        .rowSurface(isSelected: isSelected, isHovered: isHovered)
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
    }
}
