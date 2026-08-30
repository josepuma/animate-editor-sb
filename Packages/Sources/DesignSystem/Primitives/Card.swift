import SwiftUI

/// A titled panel: an optional leading status dot, a title, an optional
/// subtitle, a trailing accessory, and content beneath.
public struct Card<Content: View, Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let statusTint: Color?
    private let accessory: Accessory
    private let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        statusTint: Color? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusTint = statusTint
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            HStack(spacing: Theme.Spacing.snug) {
                if let statusTint {
                    Circle()
                        .fill(statusTint)
                        .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    Text(title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }

                Spacer(minLength: Theme.Spacing.snug)
                accessory
            }

            content
        }
        .padding(Theme.Spacing.regular)
        .surface(.panel)
    }
}
