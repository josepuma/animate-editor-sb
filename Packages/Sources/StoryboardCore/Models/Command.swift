/// Parameter command flags (`_P`).
public enum ParameterKind: String, Sendable {
    /// Horizontal flip.
    case flipHorizontal = "H"
    /// Vertical flip.
    case flipVertical = "V"
    /// Additive blending.
    case additive = "A"
}

/// Command discriminator, used for grouping without unwrapping payloads.
public enum CommandKind: String, Sendable, CaseIterable {
    case fade = "F"
    case move = "M"
    case moveX = "MX"
    case moveY = "MY"
    case scale = "S"
    case vectorScale = "V"
    case rotate = "R"
    case color = "C"
    case parameter = "P"
}

/// A storyboard command.
///
/// Ported from the discriminated union in `app/types/commands.ts`. Timing and
/// easing are shared by every case, so they live in `timing` rather than being
/// repeated in each payload.
public struct Command: Sendable {
    /// Shared timing and easing fields (`BaseCommand` in TypeScript).
    public struct Timing: Sendable {
        public var easing: Easing
        public var startTime: Double
        public var endTime: Double

        public init(easing: Easing, startTime: Double, endTime: Double) {
            self.easing = easing
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    /// Per-command payload.
    public enum Payload: Sendable {
        /// `_F` — fade.
        case fade(start: Double, end: Double)
        /// `_M` — move.
        case move(startX: Double, startY: Double, endX: Double, endY: Double)
        /// `_MX` — move on the X axis only.
        case moveX(start: Double, end: Double)
        /// `_MY` — move on the Y axis only.
        case moveY(start: Double, end: Double)
        /// `_S` — uniform scale.
        case scale(start: Double, end: Double)
        /// `_V` — non-uniform scale.
        case vectorScale(startX: Double, startY: Double, endX: Double, endY: Double)
        /// `_R` — rotate, in radians.
        case rotate(start: Double, end: Double)
        /// `_C` — colour, channels in [0, 255].
        case color(
            startR: Double, startG: Double, startB: Double,
            endR: Double, endG: Double, endB: Double,
        )
        /// `_P` — parameter flag.
        case parameter(ParameterKind)

        public var kind: CommandKind {
            switch self {
            case .fade: .fade
            case .move: .move
            case .moveX: .moveX
            case .moveY: .moveY
            case .scale: .scale
            case .vectorScale: .vectorScale
            case .rotate: .rotate
            case .color: .color
            case .parameter: .parameter
            }
        }
    }

    public var timing: Timing
    public var payload: Payload

    public init(timing: Timing, payload: Payload) {
        self.timing = timing
        self.payload = payload
    }

    public init(easing: Easing, startTime: Double, endTime: Double, payload: Payload) {
        self.init(
            timing: Timing(easing: easing, startTime: startTime, endTime: endTime),
            payload: payload,
        )
    }

    public var kind: CommandKind { payload.kind }
    public var easing: Easing { timing.easing }
    public var startTime: Double { timing.startTime }
    public var endTime: Double { timing.endTime }
}
