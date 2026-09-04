import Foundation

/// A colour in the storyboard's own terms, channels in [0, 255].
///
/// The design system speaks SwiftUI `Color`, but a parameter declaration has to
/// survive in `StoryboardCore`, which imports no UI framework — and it is the
/// same value that ends up in a `_C` command, where the channel range is what
/// osu! writes. The inspector maps this to `Color` at the edge.
public struct EffectColor: Sendable, Equatable, Hashable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let white = EffectColor(r: 255, g: 255, b: 255)

    /// The same colour rotated around the hue wheel by `amount` of a full turn.
    ///
    /// Hue rather than the channels directly: nudging red, green and blue
    /// independently walks towards grey, which is the one direction a field of
    /// confetti must not go. Rotating hue keeps every particle as saturated as
    /// the colour it came from.
    public func varied(by amount: Double) -> EffectColor {
        guard amount != 0 else { return self }

        let maximum = max(r, max(g, b)) / 255
        let minimum = min(r, min(g, b)) / 255
        let delta = maximum - minimum
        guard delta > 0 else { return self }  // Grey has no hue to rotate.

        let red = r / 255, green = g / 255, blue = b / 255
        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta
        } else if maximum == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue = (hue / 6 + amount).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }

        let saturation = maximum == 0 ? 0 : delta / maximum
        return EffectColor(hue: hue, saturation: saturation, value: maximum)
    }

    private init(hue: Double, saturation: Double, value: Double) {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))

        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))

        let (red, green, blue): (Double, Double, Double) = switch index {
        case 0: (value, t, p)
        case 1: (q, value, p)
        case 2: (p, value, t)
        case 3: (p, q, value)
        case 4: (t, p, value)
        default: (value, p, q)
        }

        self.init(r: red * 255, g: green * 255, b: blue * 255)
    }
}

/// One parameter's current value.
///
/// The cases mirror the controls the inspector can already draw, so a
/// descriptor renders without the UI knowing which effect it came from.
public enum EffectValue: Sendable, Equatable, Codable {
    case number(Double)
    case integer(Int)
    case toggle(Bool)
    case choice(String)
    case color(EffectColor)
    case text(String)
    /// A curve across the stage.
    ///
    /// The one case that does need UI of its own: a path written as numbers is
    /// a table, not a path, so it is drawn on the canvas. That breaks the rule
    /// the other six keep — that a new effect needs no new controls — and it is
    /// worth breaking exactly once, because nothing else in the system says
    /// "this shape, here".
    case path(MotionPath)

    /// Discriminator used to check a value against its declaration.
    public var kind: EffectParameter.Kind {
        switch self {
        case .number: .number
        case .integer: .integer
        case .toggle: .toggle
        case .choice: .choice
        case .color: .color
        case .text: .text
        case .path: .path
        }
    }
}

/// The declaration of one parameter: what it is called, what it accepts, and
/// what it starts at.
///
/// This is the shared contract. A native effect declares these in Swift and a
/// script will declare the same shape as JSON; the inspector only ever sees
/// declarations, never the effect that produced them.
public struct EffectParameter: Sendable, Equatable {
    /// What kind of control this parameter needs.
    public enum Kind: String, Sendable, Equatable {
        case number
        case integer
        case toggle
        case choice
        case color
        case text
        case path
    }

    /// How a numeric parameter should be presented.
    public enum Presentation: String, Sendable, Equatable {
        /// A field with a stepper — for values typed exactly.
        case field
        /// A slider — for values dialled in by feel, within a closed range.
        case slider
    }

    public let id: String
    public var name: String
    /// The group heading this parameter sits under in the inspector.
    public var group: String
    public var defaultValue: EffectValue
    /// Bounds for `.number` and `.integer`; `nil` for every other kind.
    public var range: ClosedRange<Double>?
    public var step: Double?
    /// Unit suffix shown after the value, such as `px`, `ms` or `°`.
    public var unit: String?
    /// The options a `.choice` accepts; empty for every other kind.
    public var options: [String]
    public var presentation: Presentation

    /// What has to be true elsewhere for this control to be worth showing.
    ///
    /// A ring's thickness means nothing on a square, and a slider that does
    /// nothing is a control that lies. Declared here rather than decided by the
    /// inspector so the descriptor stays the only thing the UI reads — an
    /// effect that adds a conditional parameter still needs no UI work, which
    /// is the property that makes the whole system worth having.
    public var shownWhen: Condition?

    /// Whether this parameter can be keyframed, and what animating it costs.
    ///
    /// Declared here for the same reason as ``shownWhen``: the descriptor stays
    /// the only thing the UI reads, so a filter that makes a parameter
    /// animatable needs no inspector work. The inspector learns one general
    /// rule — offer a stopwatch where this says so — rather than one rule per
    /// filter.
    ///
    /// The distinction the cases draw is not cosmetic. A parameter that ends up
    /// in a *command* animates for free, because the command was being written
    /// anyway. One that ends up in a *path* — a blur radius names a derived
    /// texture — cannot be interpolated at all: osu! draws one image for a
    /// sprite's whole life, so changing it over time means more sprites.
    public var animation: Animation

    /// What it costs to animate a parameter.
    public enum Animation: Sendable, Equatable {
        /// Not animatable. The default, because most parameters describe what a
        /// filter *is* rather than what it does over time — and a stopwatch on
        /// a structural value promises something the format cannot deliver.
        case none
        /// Lands in a command, so animating is free: the same command gets cut
        /// into one segment per keyframe pair.
        case commands
        /// Lands in a texture path, so each distinct value is another sprite.
        ///
        /// `step` is the quantisation the value is already subject to, which is
        /// what makes the cost knowable in advance: a run from 0 to 10 at a
        /// step of 2 is six textures, and the inspector can say so before
        /// anybody writes the file.
        case textures(step: Double)

        public var isAnimatable: Bool { self != .none }
    }

    /// One parameter having one of a set of values.
    public struct Condition: Sendable, Equatable {
        public let parameter: String
        public let values: [String]

        public init(parameter: String, isAnyOf values: [String]) {
            self.parameter = parameter
            self.values = values
        }

        /// Whether the condition holds for a given set of values.
        public func holds(in values: [String: EffectValue]) -> Bool {
            switch values[parameter] {
            case let .choice(option): self.values.contains(option)
            // A toggle reads as its own name: `shownWhen: .init(parameter:
            // "radial", isAnyOf: ["true"])`.
            case let .toggle(on): self.values.contains(on ? "true" : "false")
            case .none: true
            default: false
            }
        }
    }

    public init(
        id: String,
        name: String,
        group: String,
        defaultValue: EffectValue,
        range: ClosedRange<Double>? = nil,
        step: Double? = nil,
        unit: String? = nil,
        options: [String] = [],
        presentation: Presentation = .field,
        shownWhen: Condition? = nil,
        animation: Animation = .none,
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.defaultValue = defaultValue
        self.range = range
        self.step = step
        self.unit = unit
        self.options = options
        self.presentation = presentation
        self.shownWhen = shownWhen
        self.animation = animation
    }

    public var kind: Kind { defaultValue.kind }

    /// Brings `value` inside what this parameter accepts.
    ///
    /// Clamping rather than rejecting: a parameter set is edited by dragging
    /// sliders and by scripts that compute values, and both produce
    /// out-of-range numbers often enough that failing would mean every caller
    /// carries the same guard. A value of the wrong kind has no meaningful
    /// clamp, so the default stands in.
    public func coerce(_ value: EffectValue) -> EffectValue {
        guard value.kind == kind else { return defaultValue }

        switch value {
        case let .number(number):
            guard let range else { return value }
            return .number(min(max(number, range.lowerBound), range.upperBound))

        case let .integer(number):
            guard let range else { return value }
            let clamped = min(max(Double(number), range.lowerBound), range.upperBound)
            return .integer(Int(clamped.rounded()))

        case let .choice(option):
            // An option that no longer exists — a renamed preset, a script
            // edited between runs — would otherwise leave the inspector
            // showing a selection absent from its own menu.
            return options.contains(option) ? value : defaultValue

        // Nothing to clamp: a path is a shape, and any shape is a valid one.
        case .toggle, .color, .text, .path:
            return value
        }
    }

    /// The same keyframes with every value brought inside what this parameter
    /// accepts.
    ///
    /// A key is dragged in a lane that knows nothing of the parameter's range,
    /// so without this a keyframed radius could hold a number the very same
    /// parameter refuses when it is typed into the field beside it.
    public func clampingTrack(_ track: KeyframeTrack) -> KeyframeTrack {
        guard let range else { return track }
        return KeyframeTrack(
            track.keyframes.map {
                Keyframe(
                    id: $0.id,
                    time: $0.time,
                    value: min(max($0.value, range.lowerBound), range.upperBound),
                    easing: $0.easing,
                )
            },
            isEnabled: track.isEnabled,
        )
    }
}
