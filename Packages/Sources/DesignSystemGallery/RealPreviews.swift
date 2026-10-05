import CoreGraphics
import StoryboardCore
import StoryboardRendering

/// The previews the editor shows, rendered by the editor's own renderer.
///
/// The gallery used to draw its own stand-in frames — glows moving in Core
/// Graphics — and a text preset had nothing to stand in for it, so every text
/// card sat on its placeholder. Judging a card against invented frames is
/// judging it against something the app never shows; these are the frames
/// `EffectThumbnails` makes for the library, text glyphs included.
@MainActor
enum RealPreviews {
    /// Every preset the editor offers, by id.
    private static let presets: [String: EffectPreset] = Dictionary(
        (TextEffect.presets + EmitterEffect.presets + EmitterEffect.compoundPresets)
            .map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first },
    )

    /// The frames for each id that names a preset; unknown ids are left out.
    ///
    /// Synchronous on the main actor, like the renderer it calls: a few
    /// hundred milliseconds the first time a page opens, then cached by
    /// `EffectThumbnails` for every page after.
    static func frames(for ids: [String]) -> [String: [CGImage]] {
        var result: [String: [CGImage]] = [:]
        for id in ids {
            guard let preset = presets[id] else { continue }
            result[id] = EffectThumbnails.frames(for: preset)
        }
        return result
    }
}
