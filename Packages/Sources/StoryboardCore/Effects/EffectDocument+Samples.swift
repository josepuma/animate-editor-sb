import Foundation

public extension EffectDocument {
    /// Every sound the document plays, in time order.
    ///
    /// Pure and cheap by design: it reads the nodes and nothing else — no
    /// evaluator, no cache, no camera, no filters. A sample has no sprites to
    /// derive, and export and preview both ask this on every edit, so going
    /// through the evaluation pipeline would make a sound cost as much as an
    /// emitter.
    ///
    /// Hidden tracks and hidden clips are silent, a clip with no file is a
    /// placeholder, and the order is time with ties in document order
    /// (`enumerated` carries the tiebreak rather than leaning on the sort being
    /// stable).
    var samples: [StoryboardSample] {
        var collected: [StoryboardSample] = []

        for track in tracks where track.isVisible {
            for node in track.nodes where node.isVisible && node.type == SampleEffect.descriptor.type {
                // Read through the declaration, so a clip saved before a
                // parameter existed gets its default and an out-of-range value
                // is clamped.
                let context = EffectContext(descriptor: SampleEffect.descriptor, node: node)
                let path = context.text(SampleEffect.Param.file)
                guard !path.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                let choice = context.choice(SampleEffect.Param.layer)
                let layer: Layer = if choice == SampleEffect.followTrack {
                    track.layer
                } else {
                    Layer(osbName: choice)
                }

                collected.append(StoryboardSample(
                    // Never negative: a clip cannot start before 0, and the
                    // format wants a whole millisecond.
                    time: max(0, node.startTime.rounded()),
                    // The format has no Overlay for a sample.
                    layer: layer == .overlay ? .foreground : layer,
                    path: path,
                    volume: context.integer(SampleEffect.Param.volume),
                ))
            }
        }

        return collected.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }
}
