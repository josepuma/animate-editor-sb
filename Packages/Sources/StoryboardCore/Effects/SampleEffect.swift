import Foundation

/// A sound the game plays at a moment of the song.
///
/// An ``Effect`` so it is a clip like any other — it moves on the timeline,
/// copies, pastes, hides and saves in the `.aesb` with nothing new built for
/// it — but it **draws nothing**. Its sound is not produced here: the document
/// is read by `EffectDocument.samples`, a pass that skips evaluation, the cache,
/// the camera and the filters, because none of them can change when a sound
/// plays. Export and preview both read that pass.
public struct SampleEffect: Effect {
    public init() {}

    public enum Param {
        public static let file = "file"
        public static let volume = "volume"
        public static let layer = "layer"
    }

    /// The layer choice that means "whatever this clip's track is on".
    ///
    /// A choice rather than a layer stamped at placement: moving the clip to
    /// another lane then keeps meaning "this lane", the way a track colour of
    /// `nil` follows its layer.
    public static let followTrack = "Track"

    /// How long a clip is when the length of its file could not be read, in
    /// milliseconds. Short on purpose: it is a marker, not a claim about the
    /// sound, and a long guess would cover clips that are not there.
    public static let fallbackDuration: Double = 500

    public static let descriptor: EffectDescriptor = {
        var descriptor = EffectDescriptor(
            type: "sample",
            name: "Sample",
            category: .audio,
            systemImage: "speaker.wave.2",
            parameters: [
                EffectParameter(
                    id: Param.file,
                    name: "File",
                    group: "Sound",
                    defaultValue: .text(""),
                ),
                EffectParameter(
                    id: Param.volume,
                    name: "Volume",
                    group: "Sound",
                    defaultValue: .integer(100),
                    range: 0...100,
                    step: 1,
                    unit: "%",
                    presentation: .slider,
                ),
                EffectParameter(
                    id: Param.layer,
                    name: "Layer",
                    group: "Sound",
                    defaultValue: .choice(followTrack),
                    options: [followTrack, Layer.background.rawValue, Layer.fail.rawValue, Layer.pass.rawValue, Layer.foreground.rawValue],
                ),
            ],
        )
        // Its length is its file's, set once at placement: stretching a sound
        // would promise something the game does not do.
        descriptor.isResizable = false
        // Nothing to look at, so nothing to transform, filter or keyframe.
        descriptor.drawsSprites = false
        return descriptor
    }()

    public func evaluate(in _: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        []
    }
}
