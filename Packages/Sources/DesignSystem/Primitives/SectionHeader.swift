import SwiftUI

/// A heading above a group of controls, with an optional trailing accessory.
public struct SectionHeader<Accessory: View>: View {
    private let title: String
    private let accessory: Accessory

    public init(_ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Text(title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.secondary)
            Spacer(minLength: Theme.Spacing.snug)
            accessory
        }
    }
}
