import DesignSystem
import SwiftUI

/// Marks a panel whose feature is not built yet.
///
/// Explicit rather than an empty box: an unlabelled blank panel reads as a bug,
/// and a mock that pretends to work is worse than one that admits it does not.
struct ComingSoon: View {
    private let title: String
    private let detail: String
    private let systemImage: String

    init(title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.snug) {
            Image(systemName: systemImage)
                .font(Theme.Typography.emptyStateIcon)
                .foregroundStyle(Theme.Palette.tertiary)

            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondary)

            Text(detail)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.regular)
    }
}
