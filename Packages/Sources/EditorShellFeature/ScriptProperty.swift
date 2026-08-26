import SwiftUI

/// A parameter a script exposes for tweaking without editing code.
///
/// Scripting is not implemented yet, so these are sample values standing in for
/// what a script will declare. The shape is what the real feature needs: a
/// name, a kind, and a current value the inspector can bind to.
struct ScriptProperty: Identifiable {
    enum Value {
        case number(Double, unit: String?, range: ClosedRange<Double>, step: Double)
        case slider(Double, range: ClosedRange<Double>)
        case color(Color, hex: String)
        case choice(String, options: [String])
        case toggle(Bool)
        case text(String)
    }

    let id: String
    var name: String
    var value: Value
}

/// A named block of properties, as a script would group them.
struct ScriptPropertyGroup: Identifiable {
    let id: String
    var name: String
    var properties: [ScriptProperty]
}

// ─── Sample content ──────────────────────────────────────────────────────────

extension ScriptPropertyGroup {
    /// Placeholder groups showing the shape of a script's parameters.
    ///
    /// Named after the kind of storyboard work these panels will drive, so the
    /// layout can be judged against something plausible rather than lorem text.
    static func samples() -> [ScriptPropertyGroup] {
        [
            ScriptPropertyGroup(
                id: "typography",
                name: "Typography",
                properties: [
                    ScriptProperty(
                        id: "font",
                        name: "Font",
                        value: .choice("Nunito", options: ["Nunito", "Aller", "Exo 2", "Rajdhani"]),
                    ),
                    ScriptProperty(
                        id: "size",
                        name: "Size",
                        value: .number(29, unit: "px", range: 8...144, step: 1),
                    ),
                    ScriptProperty(
                        id: "weight",
                        name: "Weight",
                        value: .choice("Black", options: ["Light", "Regular", "Bold", "Black"]),
                    ),
                    ScriptProperty(
                        id: "tracking",
                        name: "Tracking",
                        value: .number(1.5, unit: "%", range: -10...50, step: 0.5),
                    ),
                ],
            ),
            ScriptPropertyGroup(
                id: "appearance",
                name: "Appearance",
                properties: [
                    ScriptProperty(
                        id: "fill",
                        name: "Colour",
                        value: .color(Color(red: 0.36, green: 1, blue: 0.58), hex: "5BFF93"),
                    ),
                    ScriptProperty(
                        id: "opacity",
                        name: "Opacity",
                        value: .slider(1, range: 0...1),
                    ),
                    ScriptProperty(
                        id: "border",
                        name: "Border",
                        value: .color(.black, hex: "000000"),
                    ),
                    ScriptProperty(
                        id: "additive",
                        name: "Additive",
                        value: .toggle(false),
                    ),
                ],
            ),
            ScriptPropertyGroup(
                id: "motion",
                name: "Motion",
                properties: [
                    ScriptProperty(
                        id: "easing",
                        name: "Easing",
                        value: .choice(
                            "Cubic Out",
                            options: ["Linear", "Quad Out", "Cubic Out", "Elastic Out"],
                        ),
                    ),
                    ScriptProperty(
                        id: "duration",
                        name: "Duration",
                        value: .number(500, unit: "ms", range: 0...10_000, step: 50),
                    ),
                    ScriptProperty(
                        id: "stagger",
                        name: "Stagger",
                        value: .number(40, unit: "ms", range: 0...2000, step: 10),
                    ),
                    ScriptProperty(
                        id: "loop",
                        name: "Loop",
                        value: .toggle(true),
                    ),
                ],
            ),
        ]
    }
}
