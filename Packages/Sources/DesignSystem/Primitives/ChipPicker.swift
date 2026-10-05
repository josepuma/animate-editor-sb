import SwiftUI

/// A compact row of mutually exclusive filters, as above an asset list.
///
/// Separate pills rather than segments in one well: each chip is its own
/// object, and the chosen one is **outlined** in the accent instead of filled.
/// A fill says "pressed"; an outline says "this is the one", and leaves the
/// chip's own tone alone so the row keeps one rhythm.
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

    public var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(items) { item in
                FilterChip(label(item), isSelected: item == selection) {
                    selection = item
                }
            }
        }
        .animation(Theme.Motion.quick, value: selection)
    }
}
