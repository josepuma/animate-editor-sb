import SwiftUI

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
                // A fixed column so a stack of rows aligns down the inspector;
                // sizing each label to its own text leaves a ragged edge.
                .frame(width: Theme.Size.propertyLabel, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Centred on the row rather than on the stack's baseline: a label long
        // enough to wrap ("Velocity Random") is two lines against a one-line
        // control, and the default alignment leaves the two sitting at
        // different heights.
        //
        // The minimum height is what keeps the rhythm even. Without it a row
        // with a wrapped label is visibly taller than its neighbours, and a
        // column of fields reads as unevenly spaced rather than as a form.
        .frame(minHeight: Theme.Size.field, alignment: .center)
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
