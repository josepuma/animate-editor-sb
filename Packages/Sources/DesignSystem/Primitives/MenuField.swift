import SwiftUI

/// A dropdown styled as a form field.
///
/// Fills the width it is given, like every other field. A `Menu` keeps its
/// intrinsic width by default — wide enough for its longest option and no more
/// — so a `Spacer` inside its label has nothing to push against: the container
/// has already shrunk around it. Widening the label content is what makes the
/// menu itself grow.
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

                    Spacer(minLength: Theme.Spacing.tight)

                    Image(systemName: "chevron.down")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The label is the menu's only content, so its width is the
                // menu's width; without this the well stretches and the button
                // inside it stays hugging its text.
                .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
