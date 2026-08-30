import SwiftUI

public extension View {
    /// Fades a glass control cluster in and out with `isRevealed`.
    ///
    /// Glass needs this rather than a plain `.opacity`. It is composed by the
    /// system instead of drawn by SwiftUI — inside a `surfaceGroup` it survives
    /// an `.opacity(0)` on the view carrying it, leaving an empty pill floating
    /// over the content with its own contents invisible. So the surface has to
    /// be withdrawn rather than faded.
    ///
    /// So the two fade in sequence: the contents go first and quickly, the glass
    /// follows at the standard pace. On the way out the pill is already empty as
    /// it dissolves, rather than emptying and vanishing in the same instant —
    /// and on the way in the surface is there before anything lands on it.
    ///
    /// - Parameter shape: the surface to apply. Capsule by default, for the
    ///   floating clusters this exists to serve.
    func revealed(
        _ isRevealed: Bool,
        role: SurfaceRole = .floating,
        capsule: Bool = true,
        radius: CGFloat? = nil,
    ) -> some View {
        modifier(
            RevealedSurface(
                isRevealed: isRevealed,
                role: role,
                isCapsule: capsule,
                radius: radius,
            ),
        )
    }
}

private struct RevealedSurface: ViewModifier {
    let isRevealed: Bool
    let role: SurfaceRole
    let isCapsule: Bool
    let radius: CGFloat?

    /// Whether the surface is drawn at all.
    @State private var isSurfaced = false

    func body(content: Content) -> some View {
        // `isCapsule` decides the shape, not which branch runs: two branches
        // would be two different views to SwiftUI, and swapping them mid-fade
        // restarts the animation from nothing.
        content
            // Fades inside the surface rather than outside it, so the contents
            // clear before the glass does. Outside, one opacity would dim both
            // together and the pill would empty and vanish at the same instant.
            .opacity(isRevealed ? 1 : 0)
            .modifier(
                SurfaceStyle(
                    role: role,
                    shape: isCapsule
                        ? AnyShape(Capsule(style: .continuous))
                        : AnyShape(
                            RoundedRectangle(
                                cornerRadius: radius ?? role.defaultRadius,
                                style: .continuous,
                            ),
                        ),
                    isEnabled: isSurfaced,
                ),
            )
            // The contents move quickly and the glass at the standard pace, so
            // on the way out the pill is already empty as it dissolves rather
            // than emptying and vanishing at once.
            .animation(Theme.Motion.quick, value: isRevealed)
            .animation(Theme.Motion.standard, value: isSurfaced)
            // Hidden controls must not swallow clicks meant for what is behind
            // them.
            .allowsHitTesting(isRevealed)
            .onChange(of: isRevealed, initial: true) { _, revealed in
                if revealed {
                    isSurfaced = true
                } else {
                    Task {
                        // Wait out the contents' own fade before withdrawing
                        // the glass they sit on.
                        try? await Task.sleep(for: .seconds(Theme.Motion.quickDuration))
                        // Guards a pointer that came back mid-fade: without it
                        // the surface would vanish under controls on their way
                        // in again.
                        if !isRevealed { isSurfaced = false }
                    }
                }
            }
    }
}
