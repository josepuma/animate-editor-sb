import DesignSystem
import SwiftUI

/// One collapsible heading in the keyframe editor: Transform, or a filter.
///
/// Shaped like the library panel's `CategoryHeader` deliberately — the same
/// chevron, icon, title and trailing count. Two things that behave alike must
/// not look unrelated, and this is the second place in the app where a list of
/// rows folds away.
///
/// The grouping is what lets a filter show *every* parameter it can animate
/// rather than only the ones already animated. Flat, a clip with three filters
/// would put fifteen rows above the nine anybody came for; folded, each filter
/// is one line until it is wanted — which is exactly how After Effects reveals
/// an effect's properties.
struct KeyframeGroupHeader: View {
    let title: String
    let systemImage: String
    /// How many of the group's properties are animated, kept visible while it
    /// is shut — that is what makes a closed heading worth reading rather than
    /// just a lid.
    let animatedCount: Int
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.snug) {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: Theme.Size.hairline * 8)

                Image(systemName: systemImage)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)

                Text(title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Only when something is animated: a zero beside every filter
                // is noise, and the absence already says the same thing.
                if animatedCount > 0 {
                    Text("\(animatedCount)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.compact)
            .frame(height: KeyframeRows.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovered ? Theme.Fill.rowHover : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
