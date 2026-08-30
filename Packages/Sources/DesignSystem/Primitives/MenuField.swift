import SwiftUI

/// A dropdown styled as a form field.
public struct MenuField<Item: Hashable & Identifiable>: View {
    private let items: [Item]
    private let label: (Item) -> String
    @Binding private var selection: Item

    public init(
        items: [Item],
        selection: Binding<Item>,
        label: @escaping (Item) -> String,
    ) {
        self.items = items
        _selection = selection
        self.label = label
    }

    public var body: some View {
        FieldWell {
            Menu {
                ForEach(items) { item in
                    Button(label(item)) { selection = item }
                }
            } label: {
                HStack(spacing: Theme.Spacing.tight) {
                    Text(label(selection))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }
}
