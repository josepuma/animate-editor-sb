import Foundation

/// A value at a moment, and how it travels to the next one.
///
/// The easing belongs to the keyframe it leaves *from*, which is how After
/// Effects and every storyboard command work: a `_M` carries its own curve, and
/// the segment between two keys is one command.
public struct Keyframe: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    /// Milliseconds from the start of the clip, not from the start of the song.
    ///
    /// Local, so moving a clip along the timeline moves its animation with it
    /// rather than leaving the keys where they were.
    public var time: Double
    public var value: Double
    /// How the value travels from here to the next keyframe.
    public var easing: Easing

    public init(id: String = UUID().uuidString, time: Double, value: Double, easing: Easing = .linear) {
        self.id = id
        self.time = time
        self.value = value
        self.easing = easing
    }
}

/// One property animated over a clip's life.
///
/// A track of keyframes replaces the `start`/`end` pairs an effect would
/// otherwise declare. Those pairs are keyframes with the count fixed at two —
/// they cannot say "here, then there, then back", which is most of what
/// animating something means.
public struct KeyframeTrack: Sendable, Equatable, Codable {
    /// Sorted by time. Kept sorted on every edit rather than at read time,
    /// because reading happens once per sprite and editing once per drag.
    public private(set) var keyframes: [Keyframe]
    /// Whether the keys are in effect.
    ///
    /// Switching animation off keeps them. Deleting a stopwatch's worth of work
    /// on one click — with no undo — is a trap: the click that turns animation
    /// on and the click that destroys it are the same click, and the second one
    /// is indistinguishable from the first until it is too late.
    public var isEnabled: Bool

    public init(_ keyframes: [Keyframe] = [], isEnabled: Bool = true) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
        self.isEnabled = isEnabled
    }

    /// A track holding one unchanging value.
    public init(constant value: Double) {
        self.init([Keyframe(time: 0, value: value)])
    }

    public var isEmpty: Bool { keyframes.isEmpty }
    /// Whether this actually animates, or is a single value wearing a track's
    /// clothes. Used to keep a still sprite from being written as a move from a
    /// place to the same place.
    public var isAnimated: Bool { isEnabled && keyframes.count > 1 }
    /// Whether the track drives its property at all.
    public var isActive: Bool { isEnabled && !keyframes.isEmpty }

    public var first: Keyframe? { keyframes.first }
    public var last: Keyframe? { keyframes.last }

    /// The value at `time`, holding the ends.
    ///
    /// Before the first key and after the last, the value is that key's — a
    /// property does not fade in from nothing because its animation has not
    /// started yet.
    public func value(at time: Double) -> Double {
        guard isEnabled, let first = keyframes.first else { return 0 }
        guard keyframes.count > 1 else { return first.value }

        if time <= first.time { return first.value }
        guard let last = keyframes.last, time < last.time else { return keyframes.last!.value }

        for (from, to) in zip(keyframes, keyframes.dropFirst()) where time < to.time {
            let span = to.time - from.time
            guard span > 0 else { return to.value }
            // The same interpolation the resolver uses, so a keyframe preview
            // and the exported command agree exactly.
            return easedLerp(from.value, to.value, (time - from.time) / span, from.easing)
        }
        return last.value
    }

    // ─── Editing ─────────────────────────────────────────────────────────────

    /// Adds a keyframe, replacing any already at that moment.
    ///
    /// Replacing rather than appending: two keys at one time is a state with no
    /// meaning — the value would be whichever the sort happened to put second.
    @discardableResult
    public mutating func set(_ value: Double, at time: Double, easing: Easing = .linear) -> Keyframe {
        let key = Keyframe(time: time, value: value, easing: easing)
        keyframes.removeAll { abs($0.time - time) < 0.5 }
        keyframes.append(key)
        keyframes.sort { $0.time < $1.time }
        return key
    }

    public mutating func remove(_ id: Keyframe.ID) {
        keyframes.removeAll { $0.id == id }
    }

    public mutating func move(_ id: Keyframe.ID, to time: Double) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[index].time = max(0, time)
        keyframes.sort { $0.time < $1.time }
    }

    public mutating func setValue(_ value: Double, for id: Keyframe.ID) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[index].value = value
    }

    public mutating func setEasing(_ easing: Easing, for id: Keyframe.ID) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[index].easing = easing
    }

    /// Stretches every key so the track spans `newDuration` instead of `old`.
    ///
    /// Resizing a clip has to carry its animation with it. Left alone, the keys
    /// stay where they were: stretch a four-second clip to twenty-six and the
    /// last twenty-two seconds hold whatever the final key said — which for a
    /// fade-out is nothing at all, so the sprite vanishes a quarter of the way
    /// through its own clip.
    public mutating func rescale(from old: Double, to newDuration: Double) {
        guard old > 0, newDuration > 0, old != newDuration else { return }
        let factor = newDuration / old
        keyframes = keyframes.map { key in
            var scaled = key
            scaled.time = key.time * factor
            return scaled
        }
    }

    /// Brings every key inside `duration`.
    ///
    /// A key past the end of its clip is an instruction with no moment to
    /// happen in, and the commands built from it run past the sprite's own life.
    public mutating func clamp(to duration: Double) {
        keyframes = keyframes.map { key in
            var clamped = key
            clamped.time = min(max(0, key.time), duration)
            return clamped
        }
        keyframes.sort { $0.time < $1.time }
    }

    /// The segments between consecutive keys, which is what becomes commands.
    ///
    /// One command per segment: a storyboard interpolates between two values
    /// with its own easing, so the shapes line up exactly.
    public var segments: [(from: Keyframe, to: Keyframe)] {
        Array(zip(keyframes, keyframes.dropFirst()))
    }
}

/// The transform properties every visual effect animates.
///
/// A fixed set rather than "any parameter": position, scale, rotation and
/// opacity are what animating something means almost all of the time, and
/// keeping the list closed means the timeline can lay them out without asking
/// each effect what it has. Anything else stays a plain parameter, and can be
/// opened up later without changing what is already here.
public enum TransformProperty: String, CaseIterable, Sendable {
    case x
    case y
    /// Horizontal scale. Paired with `scaleY`, and written as `_V` whenever the
    /// two differ — the format scales per axis, so a clip can be stretched.
    case scaleX
    case scaleY
    case rotation
    case opacity

    /// The two axes of scale, in the order they are shown.
    public static let scaleAxes: [TransformProperty] = [.scaleX, .scaleY]

    public var title: String {
        switch self {
        case .x: "Position X"
        case .y: "Position Y"
        case .scaleX: "Scale X"
        case .scaleY: "Scale Y"
        case .rotation: "Rotation"
        case .opacity: "Opacity"
        }
    }

    /// What the property is worth when nothing says otherwise.
    public var defaultValue: Double {
        switch self {
        case .x: 320
        case .y: 240
        case .scaleX, .scaleY: 1
        case .rotation: 0
        case .opacity: 1
        }
    }

    public var unit: String? {
        switch self {
        case .x, .y: "px"
        case .rotation: "°"
        case .scaleX, .scaleY, .opacity: nil
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .x: -400...1100
        case .y: -300...800
        case .scaleX, .scaleY: 0...20
        case .rotation: -1080...1080
        case .opacity: 0...1
        }
    }

    public var step: Double {
        switch self {
        case .x, .y, .rotation: 1
        case .scaleX, .scaleY, .opacity: 0.05
        }
    }
}

/// Every property of one effect: its resting value, and its animation if it
/// has one.
///
/// The two are separate on purpose, and it is the distinction After Effects
/// makes. A property is a **value** — one number, edited freely — until someone
/// turns animation on for it; only then does editing it lay down keyframes.
///
/// Collapsing the two was a real bug: with the displayed value read from the
/// playhead, moving along the timeline and typing a number planted keys nobody
/// asked for, on properties nobody was animating.
public struct Transform: Sendable, Equatable, Codable {
    private var tracks: [String: KeyframeTrack]
    /// What a property is worth when it is not animated.
    private var values: [String: Double]

    public init(tracks: [String: KeyframeTrack] = [:], values: [String: Double] = [:]) {
        self.tracks = tracks
        self.values = values
    }

    /// The resting value of a property — what it is when nothing animates it.
    ///
    /// Still meaningful while animated: turning animation off leaves this
    /// behind rather than snapping back to a system default.
    public subscript(value property: TransformProperty) -> Double {
        get { values[property.rawValue] ?? property.defaultValue }
        set { values[property.rawValue] = newValue }
    }

    public subscript(property: TransformProperty) -> KeyframeTrack {
        get { tracks[property.rawValue] ?? KeyframeTrack() }
        set {
            // An empty track is the absence of animation, not an animation of
            // nothing: dropping it keeps "is this animated" a simple question.
            // A *disabled* one is kept, since its keys are still someone's work.
            if newValue.isEmpty {
                tracks.removeValue(forKey: property.rawValue)
            } else {
                tracks[property.rawValue] = newValue
            }
        }
    }

    /// Whether a property has keyframes at all.
    public func isAnimated(_ property: TransformProperty) -> Bool {
        self[property].isAnimated
    }

    /// Properties with any keyframe on them, in declaration order.
    public var animatedProperties: [TransformProperty] {
        TransformProperty.allCases.filter { self[$0].isActive }
    }

    /// Properties holding keys, whether or not those keys are switched on.
    public var propertiesWithKeyframes: [TransformProperty] {
        TransformProperty.allCases.filter { !self[$0].isEmpty }
    }

    public var isEmpty: Bool { tracks.isEmpty }

    /// What a property is worth at a moment: its animation if it has one,
    /// otherwise its resting value.
    public func value(_ property: TransformProperty, at time: Double) -> Double {
        let track = self[property]
        return track.isActive ? track.value(at: time) : self[value: property]
    }

    /// Stretches every animated property to a new clip length.
    public mutating func rescale(from old: Double, to newDuration: Double) {
        for property in TransformProperty.allCases where !self[property].isEmpty {
            var track = self[property]
            track.rescale(from: old, to: newDuration)
            self[property] = track
        }
    }

    /// Whether *anything* about a property differs from the system default.
    public func isSet(_ property: TransformProperty) -> Bool {
        !self[property].isEmpty || values[property.rawValue] != nil
    }
}
