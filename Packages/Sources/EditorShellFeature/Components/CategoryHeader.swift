import DesignSystem
import SwiftUI

/// A category heading that folds the rows under it away.
///
/// After Effects' shape, and worth copying once a library outgrows one screen:
/// closing what you are not using is the difference between a list and a wall.
/// What is **not** copied is starting everything collapsed — AE ships two
/// hundred effects, so it has to; twenty means every session would begin with
/// six clicks before anything is visible.
package struct CategoryHeader: View {
    private let title: String
    private let systemImage: String
    private let count: Int
    private let isExpanded: Bool
    private let toggle: () -> Void

    @State private var isHovered = false

    package init(
        title: String,
        systemImage: String,
        count: Int,
        isExpanded: Bool,
        toggle: @escaping () -> Void,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.isExpanded = isExpanded
        self.toggle = toggle
    }

    package var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.snug) {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: Theme.Spacing.compact)

                Image(systemName: systemImage)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isExpanded ? Theme.Palette.accent : Theme.Palette.tertiary)

                Text(title)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(isExpanded ? Theme.Palette.primary : Theme.Palette.secondary)

                Spacer(minLength: 0)

                // The count stays while the group is shut, which is what makes
                // a closed heading worth reading rather than just a lid.
                CountBadge(count)
            }
            .padding(.horizontal, Theme.Spacing.snug)
            .frame(height: Theme.Size.control)
            .rowSurface(isHovered: isHovered)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isExpanded)
    }
}
