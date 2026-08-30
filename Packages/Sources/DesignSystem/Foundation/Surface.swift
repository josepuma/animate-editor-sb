import SwiftUI

/// What a surface is being used for.
///
/// The role decides its material, and the deciding question is *what is behind
/// it*. Glass is worth its cost only where something worth seeing sits
/// underneath — the storyboard canvas. A panel anchored to the window edge has
/// nothing behind it but the desktop, so refracting there buys no depth and
/// costs contrast on the content it holds.
///
/// Naming the role rather than the material also means the whole app restyles
/// from one place, and the fallback for systems without Liquid Glass is decided
/// once instead of at every call site.
public enum SurfaceRole {
    // ─── Opaque: anchored to the app's own chrome ────────────────────────────

    /// A panel that holds content: cards, list rows, the side panel.
    case panel

    /// A panel raised above its siblings — a popover, an active selection.
    case raised

    /// A well a control sits in, reading as sunken rather than floating.
    case inset

    /// A strip of controls anchored to the window: the toolbar, the rail.
    ///
    /// Distinct from `.floating` even though both hold controls: this one has
    /// window behind it, not content.
    case bar

    // ─── Glass: floating over the canvas ─────────────────────────────────────

    /// Controls floating over the storyboard: the transport, the coordinate
    /// readout.
    ///
    /// Carries a scrim, because glass takes its tone from what sits behind it
    /// and a storyboard frame can be any colour at all.
    case floating

    /// Deprecated spelling of `.floating`.
    @available(*, deprecated, renamed: "floating")
    public static var overlay: SurfaceRole { .floating }
}

public extension View {
    /// Applies the app's surface for `role`.
    ///
    /// - Parameter isEnabled: draws no surface at all when false. See
    ///   `capsuleSurface` for why glass needs withdrawing rather than fading.
    @ViewBuilder
    func surface(
        _ role: SurfaceRole = .panel,
        radius: CGFloat? = nil,
        isEnabled: Bool = true,
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: radius ?? role.defaultRadius,
            style: .continuous,
        )
        modifier(SurfaceStyle(role: role, shape: AnyShape(shape), isEnabled: isEnabled))
    }

    /// Applies the app's surface in a fully rounded capsule.
    ///
    /// Floating control clusters are capsules rather than rounded rectangles:
    /// a radius smaller than half the height reads as a soft-cornered box, not
    /// as a pill.
    /// - Parameter isEnabled: draws no surface at all when false.
    ///
    ///   Needed because glass is composed by the system rather than drawn by
    ///   SwiftUI: inside a `surfaceGroup` it survives an `.opacity(0)` on the
    ///   view that carries it, leaving an empty pill floating with its contents
    ///   invisible. Fading a glass surface means not asking for one.
    func capsuleSurface(_ role: SurfaceRole = .floating, isEnabled: Bool = true) -> some View {
        modifier(
            SurfaceStyle(
                role: role,
                shape: AnyShape(Capsule(style: .continuous)),
                isEnabled: isEnabled,
            ),
        )
    }

    /// Groups adjacent glass surfaces so they blend into each other rather than
    /// stacking their materials where they meet.
    ///
    /// Only affects glass; opaque surfaces are unchanged by it.
    @ViewBuilder
    func surfaceGroup() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
    }
}

// ─── Application ─────────────────────────────────────────────────────────────

/// Draws whichever material the role asks for, in the given shape.
struct SurfaceStyle: ViewModifier {
    let role: SurfaceRole
    let shape: AnyShape
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if role.isGlass {
            glass(content)
        } else {
            content
                .background(isEnabled ? role.opaqueFill : .clear, in: shape)
                .overlay {
                    // `stroke` rather than `strokeBorder`: erasing the shape to
                    // `AnyShape` drops `InsettableShape`, which is what carries
                    // the inset variant. Clipping to the same shape keeps the
                    // half of the line that would sit outside it.
                    shape
                        .stroke(
                            isEnabled ? role.borderColor : .clear,
                            lineWidth: Theme.Size.hairline * 2,
                        )
                        .clipShape(shape)
                }
        }
    }

    /// Glass, withdrawn when disabled.
    ///
    /// The `if` is on the modifier chain rather than around two different
    /// bodies of content: SwiftUI keeps the same content view either way, so
    /// what changes is one modifier rather than the whole subtree — which is
    /// what lets a surrounding animation carry the change instead of the view
    /// being swapped out from under it.
    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                // A dark veil under the glass is what keeps white glyphs
                // readable over a bright frame; the material alone adapts to
                // the backdrop and disappears against light artwork.
                .background(
                    Color.black.opacity(isEnabled ? role.scrimOpacity : 0),
                    in: shape,
                )
                .glassEffect(isEnabled ? role.liquidGlass : .identity, in: shape)
        } else {
            content
                .background(
                    isEnabled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear),
                    in: shape,
                )
                .background(Color.black.opacity(isEnabled ? role.scrimOpacity : 0), in: shape)
                .overlay {
                    shape
                        .stroke(
                            isEnabled ? role.borderColor : .clear,
                            lineWidth: Theme.Size.hairline * 2,
                        )
                        .clipShape(shape)
                }
        }
    }
}

// ─── Role definitions ────────────────────────────────────────────────────────

public extension SurfaceRole {
    /// Whether the role refracts what is behind it.
    ///
    /// Only surfaces that float over the canvas do. Everything else is anchored
    /// to the window, where there is nothing worth refracting.
    var isGlass: Bool {
        switch self {
        case .floating: true
        case .panel, .raised, .inset, .bar: false
        }
    }
}

extension SurfaceRole {
    var defaultRadius: CGFloat {
        switch self {
        case .bar: Theme.Radius.bar
        case .panel, .raised: Theme.Radius.panel
        case .inset: Theme.Radius.control
        case .floating: Theme.Radius.bar
        }
    }

    /// The fill for an opaque role, layered over the app's dark chrome.
    var opaqueFill: Color {
        switch self {
        case .panel: Theme.Fill.panel
        case .raised: Theme.Fill.raised
        case .inset: Theme.Fill.well
        case .bar: Theme.Fill.panel
        case .floating: .clear
        }
    }

    var borderColor: Color {
        switch self {
        case .panel, .bar: Theme.Border.panel
        case .raised: Theme.Border.raised
        case .inset: Theme.Border.field
        case .floating: Theme.Border.badge
        }
    }

    @available(macOS 26.0, *)
    var liquidGlass: Glass {
        switch self {
        // Floating controls read as interactive, so they respond to pointer and
        // focus rather than sitting inert.
        case .floating: .regular.interactive()
        case .panel, .raised, .inset, .bar: .regular
        }
    }

    /// A dark veil behind the material.
    ///
    /// Glass takes its tone from whatever sits behind it, so a control over a
    /// white frame ends up white too. Only surfaces that float over arbitrary
    /// artwork need this.
    var scrimOpacity: Double {
        switch self {
        case .floating: 0.28
        case .panel, .raised, .inset, .bar: 0
        }
    }
}
