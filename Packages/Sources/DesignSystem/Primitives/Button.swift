import SwiftUI

// ─── Variants ────────────────────────────────────────────────────────────────

/// What a button means in its context.
///
/// The variant carries the whole recipe — colour, surface, border — so a call
/// site names an intent rather than assembling one. Views that build their own
/// button out of a font, a padding and a background drift apart the moment a
/// second one is written.
public enum ButtonVariant: Sendable {
    /// The main action of a screen or dialogue.
    case primary
    /// A supporting action that still needs its own surface.
    case secondary
    /// An action inside content, carrying no surface of its own.
    case ghost
    /// An action that destroys something.
    case destructive
}

/// How much room a button takes.
public enum ButtonSize: Sendable {
    /// 28 — inside a bar or a dense panel.
    case small
    /// 34 — the default.
    case regular
    /// 44 — a hero action, and the most comfortable pointer target.
    case large
}

// ─── Style ───────────────────────────────────────────────────────────────────

/// The app's button, as a `ButtonStyle` so it composes with `Button` rather
/// than wrapping it.
///
/// Written as a style instead of a `ThemedButton` view, the caller keeps
/// `Button`'s own API — labels, roles, keyboard shortcuts, `.disabled` — and
/// only the appearance comes from here.
public struct ThemedButtonStyle: ButtonStyle {
    private let variant: ButtonVariant
    private let size: ButtonSize
    private let isCapsule: Bool
    private let isFullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    public init(
        variant: ButtonVariant,
        size: ButtonSize,
        isCapsule: Bool,
        isFullWidth: Bool = false,
    ) {
        self.variant = variant
        self.size = size
        self.isCapsule = isCapsule
        self.isFullWidth = isFullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        ThemedButtonBody(
            configuration: configuration,
            variant: variant,
            size: size,
            isCapsule: isCapsule,
            isFullWidth: isFullWidth,
            isEnabled: isEnabled,
        )
    }
}

/// The body is its own view so it can hold hover state; a `ButtonStyle` is a
/// value type and cannot.
private struct ThemedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: ButtonVariant
    let size: ButtonSize
    let isCapsule: Bool
    let isFullWidth: Bool
    let isEnabled: Bool

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(variant.foreground(isHovered: isHovered))
            .padding(.horizontal, size.horizontalPadding)
            // Inside the style, so the fill stretches with it.
            //
            // A `.frame(maxWidth: .infinity)` at the call site widens the
            // layout box and centres the label inside it, leaving the
            // background sized to the text — a pill floating in the middle of
            // the row rather than a button filling it. The background is
            // applied below this line, which is why the width has to be here.
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: size.height)
            .contentShape(.rect)
            .modifier(
                ButtonBackground(
                    variant: variant,
                    isCapsule: isCapsule,
                    isHovered: isHovered,
                ),
            )
            // Pressed state is opacity rather than scale: a button anchored in a
            // bar that shrinks drags the row's alignment with it.
            .opacity(configuration.isPressed ? 0.72 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Theme.Motion.quick, value: isHovered)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
            .onHover { isHovered = $0 && isEnabled }
    }
}

public extension ButtonStyle where Self == ThemedButtonStyle {
    /// The app's button.
    ///
    /// - Parameters:
    ///   - capsule: fully rounded, for controls floating over content. Bars and
    ///     clusters read as pills; buttons inside a panel do not.
    ///   - fullWidth: fills the row it is in. For the one action a section
    ///     exists for — sized to its own label, such a button reads as one
    ///     control among the fields above it rather than as the thing to press.
    ///     Here rather than a `.frame` at the call site, which widens the
    ///     layout box and centres the label while the fill stays the size of
    ///     the text.
    static func themed(
        _ variant: ButtonVariant = .secondary,
        size: ButtonSize = .regular,
        capsule: Bool = false,
        fullWidth: Bool = false,
    ) -> ThemedButtonStyle {
        ThemedButtonStyle(
            variant: variant, size: size, isCapsule: capsule, isFullWidth: fullWidth,
        )
    }
}

// ─── Recipes ─────────────────────────────────────────────────────────────────

extension ButtonVariant {
    func foreground(isHovered: Bool) -> Color {
        switch self {
        case .primary: .white
        case .destructive: Theme.Palette.danger
        case .secondary, .ghost: isHovered ? Theme.Palette.primary : Theme.Palette.secondary
        }
    }

    /// Whether the variant carries glass of its own, and which role.
    var surface: SurfaceRole? {
        switch self {
        case .secondary: .bar
        case .primary, .ghost, .destructive: nil
        }
    }

    /// A flat fill drawn behind the label, for variants with no surface.
    func fill(isHovered: Bool) -> Color {
        switch self {
        case .primary: Theme.Palette.accent
        case .ghost, .destructive: isHovered ? Theme.Fill.hover : .clear
        case .secondary: .clear
        }
    }
}

extension ButtonSize {
    var height: CGFloat {
        switch self {
        case .small: Theme.Size.controlSmall
        case .regular: Theme.Size.control
        case .large: Theme.Size.controlLarge
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: Theme.Spacing.snug
        case .regular: Theme.Spacing.compact
        case .large: Theme.Spacing.regular
        }
    }

    var font: Font {
        switch self {
        case .small: Theme.Typography.micro
        case .regular, .large: Theme.Typography.label
        }
    }

    var radius: CGFloat {
        switch self {
        case .small: Theme.Radius.small
        case .regular, .large: Theme.Radius.control
        }
    }
}

/// Draws whichever background the variant asks for: glass, a flat fill, or
/// nothing at all.
private struct ButtonBackground: ViewModifier {
    let variant: ButtonVariant
    let isCapsule: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        if let role = variant.surface {
            if isCapsule {
                content.capsuleSurface(role)
            } else {
                content.surface(role, radius: Theme.Radius.control)
            }
        } else {
            content.background(
                variant.fill(isHovered: isHovered),
                in: AnyShape(shape),
            )
        }
    }

    private var shape: any Shape {
        isCapsule
            ? Capsule(style: .continuous)
            : RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }
}
