import SwiftUI

/// A row of tools, each an icon over its name, one of them active.
///
/// The bottom bar of a phone video editor, brought to a panel: what it buys is
/// **one thing at a time**. A panel that stacks every group of controls makes
/// people scroll past five sections to reach the sixth; a row of tabs puts the
/// sixth one click away and keeps the other five out of sight.
///
/// The label is there because icons alone stop being guessable past four or
/// five — and an editor's tools are exactly the kind of thing nobody has a
/// conventional glyph for.
public struct ToolTabs<Item: Hashable & Identifiable>: View {
    private let items: [Item]
    private let icon: (Item) -> String
    private let label: (Item) -> String
    @Binding private var selection: Item

    @Namespace private var indicator

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

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                ToolTab(
                    systemImage: icon(item),
                    label: label(item),
                    isSelected: item == selection,
                    indicator: indicator,
                ) {
                    selection = item
                }
            }
        }
        .animation(Theme.Motion.standard, value: selection)
    }
}

private struct ToolTab: View {
    let systemImage: String
    let label: String
    let isSelected: Bool
    let indicator: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.tight) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.controlIcon)
                    .frame(height: Theme.Size.controlTiny)

                Text(label)
                    .font(Theme.Typography.micro)
                    .lineLimit(1)

                // The slot is always there, so a tab does not grow by three
                // points when it becomes active and shove the row.
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Theme.Palette.accent)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
                .frame(width: Theme.Size.indicatorLength, height: Theme.Size.indicator)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.snug)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }

    private var foreground: Color {
        if isSelected { return Theme.Palette.accent }
        return isHovered ? Theme.Palette.primary : Theme.Palette.secondary
    }
}
