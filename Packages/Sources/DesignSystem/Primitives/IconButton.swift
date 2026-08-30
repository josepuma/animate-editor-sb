import SwiftUI

/// A square icon button — the transport controls, toolbar actions, the timeline
/// tools to come.
///
/// Separate from `ThemedButtonStyle` because the shape is the point: a square
/// target sized to its glyph, with no label to pad around.
public struct IconButton: View {
    public enum Prominence: Sendable {
        /// Sits on an existing surface, showing a fill only on hover.
        case plain
        /// Always carries a fill.
        ///
        /// For toggles that live in a row and need to be findable at rest —
        /// per-track visibility and lock, where a control that appears only
        /// under the pointer reads as missing.
        case filled
        /// Carries its own well, for buttons that float over content.
        case surfaced
        /// The primary action in its context.
        case accented
    }

    private let systemImage: String
    private let size: CGFloat
    private let prominence: Prominence
    private let isActive: Bool
    private let help: String?
    private let action: () -> Void

    @State private var isHovered = false

    /// - Parameter isActive: whether the state the button represents is on.
    ///   An inactive toggle dims its glyph rather than changing shape, so the
    ///   row keeps its rhythm.
    public init(
        systemImage: String,
        size: CGFloat = Theme.Size.control,
        prominence: Prominence = .plain,
        isActive: Bool = true,
        help: String? = nil,
        action: @escaping () -> Void,
    ) {
        self.systemImage = systemImage
        self.size = size
        self.prominence = prominence
        self.isActive = isActive
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(SurfaceIfNeeded(prominence: prominence, radius: cornerRadius))
        // The background lights up and the glyph holds still. Scaling a button
        // this small resamples the glyph off the pixel grid, so it visibly
        // shifts inside its own frame — and scaling the whole view drags any
        // surface under it along too.
        .animation(Theme.Motion.quick, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }

    /// The glyph, sized as a fraction of its target rather than fixed.
    ///
    /// A single glyph size cannot serve every target: 15pt leaves comfortable
    /// air inside a 34pt button and almost none inside a 22pt one, where the
    /// icon fills the box and the control reads as having no padding at all.
    /// Keeping the ratio constant keeps the breathing room constant.
    private var glyphSize: CGFloat {
        (size * Self.glyphRatio).rounded()
    }

    /// Chosen so the standard 34pt button keeps the 15pt glyph it already had;
    /// the smaller sizes shrink with it instead of staying put.
    private static let glyphRatio: CGFloat = 15.0 / Theme.Size.control

    /// The corner, likewise proportional.
    ///
    /// A fixed 10pt radius on a 22pt target is nearly half its width, which
    /// rounds the control into a circle and puts it out of step with every
    /// other corner on screen.
    private var cornerRadius: CGFloat {
        min(Theme.Radius.control, size * Self.cornerRatio)
    }

    /// Matches `Radius.control` against the standard button, so the default is
    /// unchanged and only the smaller sizes tighten.
    private static let cornerRatio: CGFloat = Theme.Radius.control / Theme.Size.control

    private var foreground: Color {
        switch prominence {
        case .accented:
            return Color.white
        case .plain, .filled, .surfaced:
            if !isActive { return Theme.Palette.tertiary }
            return isHovered ? Theme.Palette.primary : Theme.Palette.secondary
        }
    }

    private var fill: Color {
        switch prominence {
        case .accented: Theme.Palette.accent
        // A surfaced button already carries its own well, so lighting up the
        // fill as well would double the shape.
        case .surfaced: .clear
        case .plain: isHovered ? Theme.Fill.hover : .clear
        case .filled: isHovered ? Theme.Fill.selected : Theme.Fill.well
        }
    }
}

/// Applies its own well only to the prominence that needs one.
private struct SurfaceIfNeeded: ViewModifier {
    let prominence: IconButton.Prominence
    /// Passed in rather than left to the role: the role's default radius is
    /// sized for a panel, and on a 22pt target it rounds the button into a
    /// circle.
    let radius: CGFloat

    func body(content: Content) -> some View {
        if prominence == .surfaced {
            content.surface(.inset, radius: radius)
        } else {
            content
        }
    }
}
