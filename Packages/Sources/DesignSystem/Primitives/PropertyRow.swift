import SwiftUI

/// A labelled field in an inspector: an optional leading control, the label,
/// the field, and an optional trailing slot.
///
/// The slots exist for controls that belong *to* the field rather than beside
/// it — a keyframe stopwatch before the label, the keyframe navigation after
/// the field. Put on a line of their own they align with nothing, and a panel
/// of five parameters becomes ten rows of alternating field and orphan.
///
/// **Inside a ``View/propertyGrid(leading:trailing:)`` the slots have fixed
/// widths, filled or not.** That is what keeps a panel a grid: a row that
/// shows its keyframe controls only while animating would otherwise shrink its
/// field when they appear, and a column of fields ends in a different place on
/// every row — the disorder a properties panel cannot afford.
public struct PropertyRow<Leading: View, Control: View, Trailing: View>: View {
    private let label: String
    private let leading: Leading
    private let control: Control
    private let trailing: Trailing

    @Environment(\.propertyGrid) private var grid

    public init(
        _ label: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder control: () -> Control,
        @ViewBuilder trailing: () -> Trailing,
    ) {
        self.label = label
        self.leading = leading()
        self.control = control()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            slot(leading, width: grid.leading)

            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                // A fixed column so a stack of rows aligns down the inspector;
                // sizing each label to its own text leaves a ragged edge.
                .frame(width: Theme.Size.propertyLabel, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            control
                .frame(maxWidth: .infinity, alignment: .leading)

            slot(trailing, width: grid.trailing)
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

    /// The slot at its grid width when there is a grid, at its own otherwise.
    ///
    /// The width is held by a `Color.clear`, with the content laid over it —
    /// not by a `.frame` on the content. A frame around a view that draws
    /// nothing (`EmptyView`, an `if` that is false) takes **no space at all**:
    /// SwiftUI drops empty views from layout, frame and all. The grid existed
    /// and reserved nothing — a row without a stopwatch started its label a
    /// column early, and a field grew to the edge until its diamond appeared
    /// and then shrank, the exact disorder the grid was written to prevent.
    @ViewBuilder
    private func slot(_ content: some View, width: CGFloat?) -> some View {
        if let width {
            Color.clear
                .frame(width: width, height: Theme.Size.controlTiny)
                .overlay(alignment: .center) { content }
        } else {
            content
        }
    }
}

public extension PropertyRow where Leading == EmptyView {
    /// A row with a trailing slot and nothing before its label.
    init(
        _ label: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder trailing: () -> Trailing,
    ) {
        self.init(label, leading: { EmptyView() }, control: control, trailing: trailing)
    }
}

public extension PropertyRow where Leading == EmptyView, Trailing == EmptyView {
    /// A row with nothing but its label and control, which is most of them.
    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.init(label, leading: { EmptyView() }, control: control, trailing: { EmptyView() })
    }
}

// ─── Grid ────────────────────────────────────────────────────────────────────

/// The fixed widths of a panel's row slots.
public struct PropertyGrid: Sendable, Equatable {
    /// The column before the label; `nil` lets each row size its own.
    public var leading: CGFloat?
    /// The column after the field; `nil` lets each row size its own.
    public var trailing: CGFloat?

    public init(leading: CGFloat? = nil, trailing: CGFloat? = nil) {
        self.leading = leading
        self.trailing = trailing
    }
}

private struct PropertyGridKey: EnvironmentKey {
    static let defaultValue = PropertyGrid()
}

public extension EnvironmentValues {
    var propertyGrid: PropertyGrid {
        get { self[PropertyGridKey.self] }
        set { self[PropertyGridKey.self] = newValue }
    }
}

public extension View {
    /// Gives every ``PropertyRow`` inside the same slot widths, so the panel
    /// is one grid whichever rows happen to fill their slots.
    ///
    /// Set once on the panel, not per row: a width that has to be remembered
    /// at each call site is a width that will be missing somewhere.
    func propertyGrid(leading: CGFloat? = nil, trailing: CGFloat? = nil) -> some View {
        environment(\.propertyGrid, PropertyGrid(leading: leading, trailing: trailing))
    }
}

// ─── Read-only value ─────────────────────────────────────────────────────────

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
