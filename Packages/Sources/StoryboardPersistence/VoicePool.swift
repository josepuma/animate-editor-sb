/// Which of a fixed set of voices a new sound goes to.
///
/// Pure bookkeeping, so the choice can be tested with no audio device: a free
/// voice first, and when every one is busy the one that started longest ago is
/// stolen. The newest sound is the one the author is listening for, so it is
/// the last to be cut.
struct VoicePool {
    private struct Voice {
        var startedAt = -Double.infinity
        var endsAt = -Double.infinity
    }

    private var voices: [Voice]

    init(capacity: Int) {
        voices = Array(repeating: Voice(), count: max(1, capacity))
    }

    /// Picks a voice for a sound starting at `start` (seconds, any shared
    /// clock) that lasts `length` seconds, and records it as busy.
    mutating func acquire(startingAt start: Double, lasting length: Double) -> Int {
        let free = voices.indices
            .filter { voices[$0].endsAt <= start }
            .min { voices[$0].endsAt < voices[$1].endsAt }
        let index = free ?? voices.indices.min { voices[$0].startedAt < voices[$1].startedAt } ?? 0
        voices[index] = Voice(startedAt: start, endsAt: start + length)
        return index
    }

    mutating func reset() {
        voices = Array(repeating: Voice(), count: voices.count)
    }
}

/// Maps the format's volume to a node gain.
enum SampleGain {
    /// 0...100 in the `.osb`, 0...1 on a node. Clamped: a hand-edited file can
    /// say anything, and a gain past 1 distorts.
    static func gain(forVolume volume: Int) -> Float {
        Float(min(max(volume, 0), 100)) / 100
    }
}
