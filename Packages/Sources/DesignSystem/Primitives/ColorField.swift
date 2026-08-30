import SwiftUI

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
                    // `controlSize` rather than a narrower frame: AppKit's
                    // colour well has its own intrinsic width, so a `.frame`
                    // clips it visually while it still claims the full space —
                    // which is what was swallowing the gap after the swatch.
                    .controlSize(.mini)
                    .fixedSize()

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
