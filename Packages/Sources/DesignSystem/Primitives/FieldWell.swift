import SwiftUI

/// The dark well every inspector control sits in.
///
/// A shared shape is what makes a column of mixed controls — numbers, menus,
/// colours — read as one form rather than as a pile of widgets.
///
/// The well fills the width it is offered, and so every control in it lines up
/// on both edges. Letting each one take its intrinsic width instead leaves a
/// menu ending wherever its longest option happens to fall, in a column where
/// the fields above and below run to the margin — a ragged edge that reads as a
/// layout fault rather than as a design.
public struct FieldWell<Content: View>: View {
    private let content: Content
    /// Whether the field inside holds the keyboard.
    ///
    /// Shown here rather than by each field, so every control that sits in a
    /// well says it the same way — and a field that gains focus without saying
    /// so leaves the keyboard somewhere invisible, which is how a space bar
    /// ends up typing instead of playing.
    private let isFocused: Bool

    public init(isFocused: Bool = false, @ViewBuilder content: () -> Content) {
        self.isFocused = isFocused
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.field)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Fill.well)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.Palette.accent : Theme.Border.field,
                        lineWidth: isFocused ? 1.5 : Theme.Size.hairline,
                    )
            }
            .animation(Theme.Motion.quick, value: isFocused)
    }
}

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
                .fill(Theme.Fill.subtle)
        }
    }
}
