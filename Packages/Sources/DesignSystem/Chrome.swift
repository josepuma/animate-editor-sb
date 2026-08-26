import SwiftUI

// ─── Sidebar rail ────────────────────────────────────────────────────────────

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
        if isSelected { return .white.opacity(0.12) }
        return isHovered ? .white.opacity(0.06) : .clear
    }
}

// ─── Section header ──────────────────────────────────────────────────────────

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

// ─── Segmented chips ─────────────────────────────────────────────────────────

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
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(item == selection ? .white.opacity(0.12) : .clear)
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

// ─── Property row ────────────────────────────────────────────────────────────

/// A labelled field in an inspector: label on the left, control on the right.
public struct PropertyRow<Control: View>: View {
    private let label: String
    private let control: Control

    public init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(width: 58, alignment: .leading)

            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A read-only value in an inspector, styled to match an editable field.
public struct PropertyValue: View {
    private let text: String
    private let isMonospaced: Bool

    public init(_ text: String, monospaced: Bool = false) {
        self.text = text
        isMonospaced = monospaced
    }

    public var body: some View {
        Text(text)
            .font(isMonospaced ? Theme.Typography.readout : Theme.Typography.micro)
            .foregroundStyle(Theme.Palette.secondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.inset, radius: Theme.Radius.small)
    }
}

// ─── Placeholder ─────────────────────────────────────────────────────────────

/// Marks a panel whose feature is not built yet.
///
/// Explicit rather than an empty box: an unlabelled blank panel reads as a bug,
/// and a mock that pretends to work is worse than one that admits it does not.
public struct ComingSoon: View {
    private let title: String
    private let detail: String
    private let systemImage: String

    public init(title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.snug) {
            Image(systemName: systemImage)
                .font(Theme.Typography.emptyStateIcon)
                .foregroundStyle(Theme.Palette.tertiary)

            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondary)

            Text(detail)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.regular)
    }
}
