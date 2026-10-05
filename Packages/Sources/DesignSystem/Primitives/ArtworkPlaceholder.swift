import SwiftUI

/// What stands where a picture will be, or cannot be: a flat plate and a glyph.
///
/// **Flat on purpose.** The system draws no decorative gradients — coloured
/// glows over a dark ground are the signature of generated design, and they
/// make every empty tile look like content when it is the absence of content.
/// The only gradients the app draws are black scrims under text laid over a
/// picture, which exist to keep the text readable and for nothing else.
///
/// A placeholder that admits it is one reads as honest; the glyph says what
/// belongs here.
public struct ArtworkPlaceholder: View {
    private let systemImage: String?
    private let tint: Color?

    /// - Parameter tint: colours the glyph only — a missing file in the warning
    ///   colour, say. The plate stays the same tone everywhere.
    public init(systemImage: String? = nil, tint: Color? = nil) {
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.Tone.well

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(
                            size: (min(proxy.size.width, proxy.size.height) * 0.3).rounded(),
                            weight: .light,
                        ))
                        .foregroundStyle(tint ?? Theme.Palette.tertiary)
                }
            }
        }
    }
}
