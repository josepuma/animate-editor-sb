import SwiftUI

/// A floating horizontal bar of controls.
///
/// The transport, the stats readout and the room switcher all share this shape,
/// so they share this container.
public struct FloatingBar<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Theme.Spacing.regular, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.compact)
        .surface(.bar)
    }
}

/// A short vertical rule for separating items inside a bar.
public struct BarDivider: View {
    public init() {}

    public var body: some View {
        Divider().frame(height: Theme.Size.dividerHeight)
    }
}
