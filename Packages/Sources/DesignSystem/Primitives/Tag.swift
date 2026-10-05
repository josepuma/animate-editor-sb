import SwiftUI

/// A labelled pill with an optional glyph — a clip's name over a lane, a
/// category, anything that is a *thing* rather than an action.
///
/// Chosen ones are outlined in the accent, never filled: the tag keeps its own
/// tone, so a row of them reads as a row of objects with one of them marked,
/// not as a toolbar with one button held down.
public struct Tag: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let action: (() -> Void)?

    @State private var isHovered = false

    /// - Parameter action: makes the tag clickable. Without one it is a label
    ///   and does not react to the pointer — a hover state on something that
    ///   cannot be clicked is a promise it does not keep.
    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        action: (() -> Void)? = nil,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .animation(Theme.Motion.quick, value: isHovered)
        } else {
            content
        }
    }

    private var content: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)

        return HStack(spacing: Theme.Spacing.snug) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.label)
            }
            Text(title)
                .font(Theme.Typography.label)
                .lineLimit(1)
        }
        .foregroundStyle(isSelected || isHovered ? Theme.Palette.primary : Theme.Palette.secondary)
        .padding(.horizontal, Theme.Spacing.compact)
        .frame(height: Theme.Size.control)
        .background(shape.fill(isHovered && !isSelected ? Theme.Tone.well : Theme.Tone.raised))
        .overlay {
            shape.strokeBorder(
                isSelected ? Theme.Palette.accent : .clear,
                lineWidth: Theme.Size.ring,
            )
        }
        .contentShape(shape)
    }
}
