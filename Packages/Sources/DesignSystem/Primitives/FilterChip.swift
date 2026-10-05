import SwiftUI

/// One pill in a row of filters — "All", "Emitter", "Audio".
///
/// Its own primitive so every row of chips in the app is the same chip. The
/// library panel had written its own, with a lighter fill for the chosen one,
/// beside a `ChipPicker` that outlines it in the accent: two chips side by side
/// meaning the same thing and saying it two ways.
public struct FilterChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    @State private var isHovered = false

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(isSelected || isHovered ? Theme.Palette.primary : Theme.Palette.secondary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.compact)
                .frame(height: Theme.Size.controlSmall)
                .background(Capsule(style: .continuous).fill(Theme.Tone.well))
                // Outlined, not filled: the chosen chip keeps its tone, and the
                // accent ring says "this one" the way it does everywhere else.
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: Theme.Size.ring)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
    }
}
