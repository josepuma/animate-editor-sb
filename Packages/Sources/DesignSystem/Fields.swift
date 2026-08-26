import SwiftUI

// ─── Field container ─────────────────────────────────────────────────────────

/// The dark well every inspector control sits in.
///
/// A shared shape is what makes a column of mixed controls — numbers, menus,
/// colours — read as one form rather than as a pile of widgets.
public struct FieldWell<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(height: Theme.Size.field)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }
    }
}

// ─── Menu field ──────────────────────────────────────────────────────────────

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

// ─── Number field ────────────────────────────────────────────────────────────

/// A numeric value with stepper arrows and an optional unit.
public struct NumberField: View {
    @Binding private var value: Double
    private let unit: String?
    private let step: Double
    private let range: ClosedRange<Double>
    private let format: String

    public init(
        value: Binding<Double>,
        unit: String? = nil,
        step: Double = 1,
        range: ClosedRange<Double> = -.infinity...(.infinity),
        format: String = "%.0f",
    ) {
        _value = value
        self.unit = unit
        self.step = step
        self.range = range
        self.format = format
    }

    public var body: some View {
        FieldWell {
            HStack(spacing: Theme.Spacing.tight) {
                Text(String(format: format, value))
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.secondary)

                if let unit {
                    Text(unit)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }

                Spacer(minLength: 0)

                Stepper(
                    "",
                    value: Binding(
                        get: { value },
                        set: { value = min(max(range.lowerBound, $0), range.upperBound) },
                    ),
                    step: step,
                )
                .labelsHidden()
                .controlSize(.mini)
            }
        }
    }
}

// ─── Colour field ────────────────────────────────────────────────────────────

/// A colour swatch with its hex value, as an inspector row.
public struct ColorField: View {
    @Binding private var color: Color
    private let hex: String

    public init(color: Binding<Color>, hex: String) {
        _color = color
        self.hex = hex
    }

    public var body: some View {
        FieldWell {
            HStack(spacing: Theme.Spacing.snug) {
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28)

                Text(hex)
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.secondary)

                Spacer(minLength: 0)

                Text("Hex")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
        }
    }
}

// ─── Slider field ────────────────────────────────────────────────────────────

/// A slider with its value shown alongside.
public struct SliderField: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let format: String

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        format: String = "%.2f",
    ) {
        _value = value
        self.range = range
        self.format = format
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Slider(value: $value, in: range)
                .controlSize(.mini)

            Text(String(format: format, value))
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.secondary)
                // Fixed width so the slider does not jump as digits change.
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// ─── Segmented icons ─────────────────────────────────────────────────────────

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
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(item == selection ? .white.opacity(0.12) : .clear)
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
                .fill(.white.opacity(0.06))
        }
        .animation(Theme.Motion.quick, value: selection)
    }
}

// ─── Toggle field ────────────────────────────────────────────────────────────

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

// ─── Group ───────────────────────────────────────────────────────────────────

/// A titled block of fields, separated from its neighbours by its own surface.
public struct FieldGroup<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            if let title {
                Text(title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
            content
        }
        .padding(Theme.Spacing.compact)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .fill(.white.opacity(0.03))
        }
    }
}
