import DesignSystem
import SwiftUI

/// One collapsible heading in the keyframe editor: Transform, or a filter.
///
/// The only place in the app where a list of rows folds away: chevron, icon,
/// title and trailing count. (The library's filters used to fold too, with a
/// header of the same shape; they are category chips now.)
///
/// The grouping is what lets a filter show *every* parameter it can animate
/// rather than only the ones already animated. Flat, a clip with three filters
/// would put fifteen rows above the nine anybody came for; folded, each filter
/// is one line until it is wanted — which is exactly how After Effects reveals
/// an effect's properties.
package struct KeyframeGroupHeader: View {
    private let title: String
    private let systemImage: String
    /// How many of the group's properties are animated, kept visible while it
    /// is shut — that is what makes a closed heading worth reading rather than
    /// just a lid.
    private let animatedCount: Int
    private let isExpanded: Bool
    private let toggle: () -> Void

    @State private var isHovered = false

    package init(
        title: String,
        systemImage: String,
        animatedCount: Int,
        isExpanded: Bool,
        toggle: @escaping () -> Void,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.animatedCount = animatedCount
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
                    .foregroundStyle(animatedCount > 0 ? Theme.Palette.accent : Theme.Palette.tertiary)

                Text(title)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isExpanded ? Theme.Palette.primary : Theme.Palette.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Only when something is animated: a zero beside every filter
                // is noise, and the absence already says the same thing. In
                // the accent because animated keys are live.
                if animatedCount > 0 {
                    CountBadge(animatedCount, isAccented: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.snug)
            .frame(height: KeyframeRows.rowHeight)
            .rowSurface(isHovered: isHovered)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }
}
