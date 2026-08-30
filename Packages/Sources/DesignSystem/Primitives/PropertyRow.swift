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
