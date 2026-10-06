import SwiftUI

/// A row of icon buttons acting as one exclusive choice, as used for alignment.
public struct IconSegments<Item: Hashable & Identifiable>: View {
    private let items: [Item]
    private let icon: (Item) -> String
    private let label: (Item) -> String
    @Binding private var selection: Item

    public init(
        items: [Item],
        selection: Binding<Item>,
        icon: @escaping (Item) -> String,
        label: @escaping (Item) -> String,
    ) {
        self.items = items
        _selection = selection
        self.icon = icon
        self.label = label
    }

    /// The segments sit concentrically inside the group's own shape.
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
                    Image(systemName: icon(item))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(
                            item == selection ? Theme.Palette.accent : Theme.Palette.tertiary,
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.controlSmall)
                        // Outlined, like every other chosen thing: the accent
                        // ring rather than a lighter fill.
                        .overlay {
                            RoundedRectangle(cornerRadius: itemRadius, style: .continuous)
                                .strokeBorder(
                                    item == selection ? Theme.Palette.accent : .clear,
                                    lineWidth: Theme.Size.ring,
                                )
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(label(item))
            }
        }
        .padding(Theme.Spacing.hair)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Tone.well)
        }
        .animation(Theme.Motion.quick, value: selection)
    }
}
