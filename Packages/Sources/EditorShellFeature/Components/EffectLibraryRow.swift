import DesignSystem
import SwiftUI

/// One effect available to place.
package struct EffectLibraryRow: View {
    private let name: String
    private let systemImage: String
    /// The category's name, shown as the second line.
    private let category: String
    private let add: () -> Void
    /// The tile's colour. `nil` keeps it neutral.
    private let tint: Color?

    @State private var isHovered = false

    package init(
        name: String,
        systemImage: String,
        category: String,
        add: @escaping () -> Void,
        tint: Color? = nil,
    ) {
        self.name = name
        self.systemImage = systemImage
        self.category = category
        self.add = add
        self.tint = tint
    }

    package var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.Spacing.compact) {
                GlyphTile(systemImage: systemImage, tint: tint, size: Theme.Size.controlSmall)

                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    Text(name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.primary)
                    Text(category)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }

                Spacer(minLength: Theme.Spacing.tight)

                AddBadge(isHighlighted: isHovered)
            }
            .padding(.horizontal, Theme.Spacing.snug)
            .frame(height: Theme.Size.controlLarge)
            .rowSurface(isHovered: isHovered)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .help("Add \(name) at the playhead")
    }
}
