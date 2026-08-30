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
                            item == selection ? Theme.Palette.primary : Theme.Palette.tertiary,
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.controlSmall)
                        .background {
                            RoundedRectangle(cornerRadius: itemRadius, style: .continuous)
                                .fill(item == selection ? Theme.Fill.selected : .clear)
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
                .fill(Theme.Fill.well)
        }
        .animation(Theme.Motion.quick, value: selection)
    }
}

/// A labelled switch.
public struct ToggleField: View {
    private let label: String
    @Binding private var isOn: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    public var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)

            Spacer(minLength: Theme.Spacing.snug)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.mini)
        }
    }
}
