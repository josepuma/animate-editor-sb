import StoryboardCore

/// What a clip's block on the timeline offers, decided by its effect.
///
/// Pure and apart from the row view so the rules can be tested without one:
/// the row is a thousand lines of gestures, and "a sound has no resize bars"
/// is not something to find out by dragging.
enum ClipBlockRule {
    /// Whether the selection frame carries grab bars at its ends.
    ///
    /// A sound's length is its file's, so bars that promise to stretch it would
    /// promise something the game does not do. Unknown effects keep them: the
    /// safe reading of "no descriptor" is the clip everyone else is.
    static func showsResizeBars(_ descriptor: EffectDescriptor?) -> Bool {
        descriptor?.isResizable ?? true
    }

    /// The glyphs a block wears at its right end: its filters, or — with none —
    /// what kind of clip it is.
    ///
    /// A sound wears its own speaker; the sparkles stand for "an effect", which
    /// a sound is not.
    static func badges(filterIcons: [String], descriptor: EffectDescriptor?) -> [String] {
        if let descriptor, !descriptor.drawsSprites { return [descriptor.systemImage] }
        return filterIcons.isEmpty ? ["sparkles"] : filterIcons
    }
}
