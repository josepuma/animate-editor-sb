import SwiftUI

/// A vertical strip of icon buttons down the edge of the window, as used for
/// switching what the side panel shows.
public struct SidebarRail<Item: Hashable & Identifiable>: View {
    private let items: [Item]
    private let icon: (Item) -> String
    private let label: (Item) -> String
    @Binding private var selection: Item

    /// Drives the indicator sliding between items rather than blinking from one
    /// to the next — the eye follows a moving light, and loses a jumping one.
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
        VStack(spacing: Theme.Spacing.tight) {
            ForEach(items) { item in
                RailButton(
                    systemImage: icon(item),
                    label: label(item),
                    isSelected: item == selection,
                    indicator: indicator,
                ) {
                    selection = item
                }
            }
        }
        .padding(.vertical, Theme.Spacing.snug)
        .padding(.horizontal, Theme.Spacing.tight)
        .animation(Theme.Motion.standard, value: selection)
    }
}

private struct RailButton: View {
    let systemImage: String
    let label: String
    let isSelected: Bool
    let indicator: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.controlIcon)
                // The accent says *this one*; no fill behind it. A lit glyph
                // and a small pill carry the selection, so the rail stays a
                // column of icons instead of becoming a column of tiles.
                .foregroundStyle(foreground)
                .frame(width: Theme.Size.control, height: Theme.Size.control)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isHovered && !isSelected ? Theme.Fill.hover : .clear)
                }
                .overlay(alignment: .leading) {
                    if isSelected {
                        Capsule()
                            .fill(Theme.Palette.accent)
                            .frame(width: Theme.Size.indicator, height: Theme.Size.indicatorLength)
                            // Into the rail's own padding, so the pill sits at
                            // the edge without pushing the glyph off centre.
                            .offset(x: -Theme.Spacing.tight)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }

    private var foreground: Color {
        if isSelected { return Theme.Palette.accent }
        return isHovered ? Theme.Palette.primary : Theme.Palette.tertiary
    }
}
