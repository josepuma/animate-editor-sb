import DesignSystem
import SwiftUI

/// One filter on a track: its name, a switch, and a body that folds away.
///
/// Only the chrome. What goes inside is the filter's parameters, which are
/// generated from its descriptor by whoever owns the model — this knows how a
/// filter *looks* as a row of a list and nothing about what one *is*.
package struct FilterCard<Content: View>: View {
    private let name: String
    private let systemImage: String
    private let isEnabled: Bool
    private let toggle: () -> Void
    private let remove: () -> Void
    private let content: Content

    @State private var isExpanded = true

    package init(
        name: String,
        systemImage: String,
        isEnabled: Bool,
        toggle: @escaping () -> Void,
        remove: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
    ) {
        self.name = name
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.toggle = toggle
        self.remove = remove
        self.content = content()
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.snug) {
                // Filters share one colour — the keyframe palette's filter
                // family — so a filter looks the same on a clip as it does in
                // the library it came from.
                GlyphTile(systemImage: systemImage, tint: Theme.KeyframePalette.filter, size: Theme.Size.controlSmall)
                    // Dimmed rather than hidden when off: a filter switched off
                    // is still part of the look someone is building.
                    .saturation(isEnabled ? 1 : 0)
                    .opacity(isEnabled ? 1 : 0.5)

                Text(name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(isEnabled ? Theme.Palette.primary : Theme.Palette.tertiary)

                Spacer(minLength: Theme.Spacing.tight)

                IconButton(
                    systemImage: isEnabled ? "eye" : "eye.slash",
                    size: Theme.Size.controlTiny,
                    isActive: isEnabled,
                    help: isEnabled ? "Disable" : "Enable",
                    action: toggle,
                )

                IconButton(
                    systemImage: "trash",
                    size: Theme.Size.controlTiny,
                    help: "Remove \(name)",
                    action: remove,
                )

                Image(systemName: "chevron.down")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .frame(width: Theme.Spacing.compact)
            }
            .padding(Theme.Spacing.snug)
            .contentShape(.rect)
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                    content
                }
                .padding(.horizontal, Theme.Spacing.compact)
                .padding(.top, Theme.Spacing.snug)
                .padding(.bottom, Theme.Spacing.compact)
                // A hairline between head and body, so an open card reads as
                // a title over its settings rather than as one block of rows.
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.Border.panel)
                        .frame(height: Theme.Size.hairline)
                }
            }
        }
        // This one keeps a surface, and the distinction is worth naming: a
        // filter is a **row of a list** — collapsible, switchable, removable —
        // not a section of a panel. Several of them stacked need to read as
        // separate items, which spacing alone cannot say.
        .background(shape.fill(Theme.Tone.raised))
        .overlay { shape.strokeBorder(Theme.Border.card, lineWidth: Theme.Size.hairline) }
        .clipShape(shape)
        .animation(Theme.Motion.quick, value: isExpanded)
        .animation(Theme.Motion.quick, value: isEnabled)
    }
}
