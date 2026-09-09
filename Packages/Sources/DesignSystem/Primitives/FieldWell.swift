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
/// A titled block of fields.
///
/// **A heading and space, not a card.** It used to draw its own filled
/// rectangle, and a panel of them was boxes inside a box: the inspector already
/// sits on `.panel`, so every group added a second surface over the first, and
/// several stacked read as a list of tiles rather than as one panel with
/// sections in it.
///
/// What separates one group from the next is the heading and the gap around
/// it — the same thing that separates paragraphs in any document, and what the
/// lyrics panel does. `Theme.Fill.subtle` is still there for a surface that
/// genuinely needs to read as inset; a group of fields is not one.
public struct FieldGroup<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            if let title {
                SectionHeader(title)
            }
            content
        }
    }
}

/// A column of ``FieldGroup``s with a rule between them.
///
/// Between, not before: a group cannot know whether it is first, and a rule on
/// the first one separates it from nothing. Placed at each call site instead it
/// gets forgotten — the inspector had one before its filters and one after the
/// track summary, while Timing, Transform and Content, generated in a
/// `ForEach`, ran together with nothing between them.
///
/// A separator that has to be remembered is a separator that will be missing
/// somewhere.
public struct FieldGroups<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        // `_VariadicView` is what lets a container see its children
        // individually — a plain `VStack` receives them already composed, with
        // no way to put anything between.
        _VariadicView.Tree(Layout()) { content }
    }

    private struct Layout: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                ForEach(children) { child in
                    if child.id != children.first?.id {
                        // Dimmed: a hairline at full contrast in a dark panel
                        // reads as a border around what follows, which is the
                        // card `FieldGroup` stopped drawing.
                        Divider().opacity(0.4)
                    }
                    child
                }
            }
        }
    }
}
