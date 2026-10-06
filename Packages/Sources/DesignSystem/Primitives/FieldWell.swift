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

/// A titled block of fields, on a surface one tone above the panel.
///
/// **A surface again, and on purpose.** It was a card once, dropped because a
/// panel of filled, bordered groups read as boxes inside a box — with
/// translucent fills and a hairline around each, every group was a tile. The
/// tone system changed what a surface is: no border, just a step lighter than
/// what it sits on. A group as a tone step is what tells one group from the
/// next at a glance, which a heading and some space were not doing once the
/// inspector held a dozen of them.
///
/// The title is an `overline` — small capitals — so it labels the rows under
/// it instead of reading as one more of them.
public struct FieldGroup<Content: View>: View {
    private let title: String?
    private let isSurfaced: Bool
    private let content: Content

    /// - Parameter surfaced: false for a group whose rows are cards of their
    ///   own — a card on a card of the same tone is the box in a box this
    ///   surface was once removed for.
    public init(_ title: String? = nil, surfaced: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        isSurfaced = surfaced
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if let title {
                Text(title)
                    .font(Theme.Typography.overline)
                    .tracking(Theme.Typography.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .lineLimit(1)
                    // Room under the title, more than between rows: it heads
                    // the group rather than being its first line.
                    .padding(.bottom, Theme.Spacing.tight)
            }
            content
        }
        .padding(isSurfaced ? Theme.Spacing.compact : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSurfaced {
                RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                    .fill(Theme.Tone.raised)
            }
        }
    }
}

/// A column of ``FieldGroup``s, one gap between each.
///
/// It drew a rule between groups while they were headings on the panel; now
/// each group is its own surface and the gap is the separator. It stays a
/// container rather than a `VStack` at each call site so the spacing between
/// groups is decided once — Timing, Transform and Content, generated in a
/// `ForEach`, once ran together because a call site forgot.
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
            // No rule between groups any more: each is its own surface, and a
            // line between two surfaces says nothing the gap does not.
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                ForEach(children) { child in
                    child
                }
            }
        }
    }
}
