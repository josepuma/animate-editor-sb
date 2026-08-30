import SwiftUI

/// A compact row of mutually exclusive filters, as above an asset list.
public struct ChipPicker<Item: Hashable & Identifiable>: View {
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

    /// The chips sit concentrically inside the picker's own shape.
    ///
    /// Computed rather than stored: Swift forbids stored statics on a generic
    /// type, and this is a pure function of two tokens anyway.
    private var itemRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.control, inset: Theme.Spacing.hair)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.hair) {
            ForEach(items) { item in
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(
                            item == selection ? Theme.Palette.primary : Theme.Palette.tertiary,
                        )
                        .padding(.horizontal, Theme.Spacing.snug)
                        .padding(.vertical, Theme.Spacing.tight)
                        .background {
                            RoundedRectangle(cornerRadius: itemRadius, style: .continuous)
                                .fill(item == selection ? Theme.Fill.selected : .clear)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.hair)
        .surface(.inset, radius: Theme.Radius.control)
        .animation(Theme.Motion.quick, value: selection)
    }
}
