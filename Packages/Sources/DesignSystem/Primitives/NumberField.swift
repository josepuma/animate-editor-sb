import SwiftUI

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
                .frame(width: Theme.Size.valueReadout, alignment: .trailing)
        }
    }
}
