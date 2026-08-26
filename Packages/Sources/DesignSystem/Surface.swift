import SwiftUI

/// What a glass surface is being used for.
///
/// Naming the role rather than the material means the whole app restyles from
/// one place, and the fallback for systems without Liquid Glass is decided once
/// instead of at every call site.
public enum SurfaceRole {
    /// A floating bar over content: the transport, the stats readout.
    case bar
    /// A panel that holds content: cards, list rows, the timeline track area.
    case panel
    /// A panel raised above its siblings — a popover or an active selection.
    case raised
    /// An area that reads as inset rather than floating, such as a well a
    /// control sits in.
    case inset
    /// Controls floating directly over artwork.
    ///
    /// A middle weight: fully clear glass leaves white glyphs invisible against
    /// a bright frame, while heavier glass turns the artwork milky. This keeps
    /// enough blur to read against anything without frosting the image.
    case overlay
}

public extension View {
    /// Applies the app's glass material for `role`.
    ///
    /// Uses Liquid Glass where the system provides it, and falls back to the
    /// previous translucent material elsewhere.
    @ViewBuilder
    func surface(_ role: SurfaceRole = .panel, radius: CGFloat? = nil) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: radius ?? role.defaultRadius,
            style: .continuous,
        )

        if #available(macOS 26.0, *) {
            self.glassEffect(role.liquidGlass, in: shape)
        } else {
            self
                .background(role.fallbackMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(role.fallbackBorderOpacity),
                        lineWidth: Theme.Size.hairline,
                    ),
                )
        }
    }

    /// Applies the app's glass material in a fully rounded capsule.
    ///
    /// Floating control clusters are capsules rather than rounded rectangles:
    /// a radius smaller than half the height reads as a soft-cornered box, not
    /// as a pill.
    @ViewBuilder
    func capsuleSurface(_ role: SurfaceRole = .bar) -> some View {
        let shape = Capsule(style: .continuous)

        if #available(macOS 26.0, *) {
            self
                // A dark veil under the glass is what keeps white glyphs
                // readable over a bright frame; the material alone adapts to
                // the backdrop and disappears against light artwork.
                .background(Color.black.opacity(role.scrimOpacity), in: shape)
                .glassEffect(role.liquidGlass, in: shape)
        } else {
            self
                .background(role.fallbackMaterial, in: shape)
                .background(Color.black.opacity(role.scrimOpacity), in: shape)
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(role.fallbackBorderOpacity),
                        lineWidth: Theme.Size.hairline,
                    ),
                )
        }
    }

    /// Groups adjacent glass surfaces so they blend into each other rather than
    /// stacking their materials where they meet.
    @ViewBuilder
    func surfaceGroup() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
    }
}

// ─── Role definitions ────────────────────────────────────────────────────────

extension SurfaceRole {
    var defaultRadius: CGFloat {
        switch self {
        case .bar: Theme.Radius.bar
        case .panel: Theme.Radius.panel
        case .raised: Theme.Radius.panel
        case .inset: Theme.Radius.control
        case .overlay: Theme.Radius.bar
        }
    }

    @available(macOS 26.0, *)
    var liquidGlass: Glass {
        switch self {
        case .bar: .regular
        case .panel: .regular
        // Raised surfaces read as interactive, so they respond to pointer and
        // focus rather than sitting inert.
        case .raised: .regular.interactive()
        case .inset: .regular
        case .overlay: .regular.interactive()
        }
    }

    var fallbackMaterial: Material {
        switch self {
        case .bar: .ultraThinMaterial
        case .panel: .thinMaterial
        case .raised: .regularMaterial
        case .inset: .ultraThinMaterial
        case .overlay: .ultraThinMaterial
        }
    }

    /// A dark veil behind the material.
    ///
    /// Glass takes its tone from whatever sits behind it, so a control over a
    /// white frame ends up white too. Only surfaces that float over arbitrary
    /// artwork need this; panels already sit on the app's own dark chrome.
    var scrimOpacity: Double {
        switch self {
        case .overlay: 0.28
        case .bar, .panel, .raised, .inset: 0
        }
    }

    /// The hairline that gives a fallback surface an edge; Liquid Glass shapes
    /// its own, so this applies only to the fallback path.
    var fallbackBorderOpacity: Double {
        switch self {
        case .bar: 0.12
        case .panel: 0.10
        case .raised: 0.16
        case .inset: 0.06
        case .overlay: 0.2
        }
    }
}
