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

    /// Whether the well hides its plate until the pointer or the keyboard
    /// arrives.
    ///
    /// For places where fields sit in a **column of many** — a timeline's
    /// keyframe rows — rather than in a panel of a few. A dozen filled plates
    /// stacked up read as the chrome rather than as the values, and the value
    /// is the thing anyone is scanning for. The well is still there the moment
    /// it matters: on hover, and while it holds the keyboard.
    private let isGhost: Bool
    @State private var isHovered = false

    public init(
        isFocused: Bool = false,
        isGhost: Bool = false,
        @ViewBuilder content: () -> Content,
    ) {
        self.isFocused = isFocused
        self.isGhost = isGhost
        self.content = content()
    }

    /// Whether the plate and border are drawn right now.
    private var showsWell: Bool { !isGhost || isHovered || isFocused }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.field)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(showsWell ? Theme.Fill.well : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.Palette.accent
                            : (showsWell ? Theme.Border.field : .clear),
                        lineWidth: isFocused ? 1.5 : Theme.Size.hairline,
                    )
            }
            // Only a ghost listens: a well that is always drawn has no reason
            // to track the pointer, and a hover test per field in a panel of
            // thirty is thirty tests for nothing.
            .onHover { if isGhost { isHovered = $0 } }
            .animation(Theme.Motion.quick, value: showsWell)
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
