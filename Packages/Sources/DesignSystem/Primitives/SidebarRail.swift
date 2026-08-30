import SwiftUI

/// A vertical strip of icon buttons down the edge of the window, as used for
/// switching what the side panel shows.
public struct SidebarRail<Item: Hashable & Identifiable>: View {
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

    public var body: some View {
        VStack(spacing: Theme.Spacing.tight) {
            ForEach(items) { item in
                RailButton(
                    systemImage: icon(item),
                    label: label(item),
                    isSelected: item == selection,
                ) {
                    selection = item
                }
            }
        }
        .padding(.vertical, Theme.Spacing.snug)
        .padding(.horizontal, Theme.Spacing.tight)
    }
}

private struct RailButton: View {
    let systemImage: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.controlIcon)
                .foregroundStyle(isSelected ? Theme.Palette.primary : Theme.Palette.tertiary)
                .frame(width: Theme.Size.control, height: Theme.Size.control)
                .background {
                    // Only the selected item carries a fill, so the rail reads
                    // as one control rather than a row of buttons.
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(fillColor)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
    }

    private var fillColor: Color {
        if isSelected { return Theme.Fill.selected }
        return isHovered ? Theme.Fill.hover : .clear
    }
}
