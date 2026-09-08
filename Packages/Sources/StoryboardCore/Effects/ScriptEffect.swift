import Foundation

/// A clip whose sprites come from code the author wrote.
///
/// An `Effect` like any other, which is the whole design: it inherits the
/// clip's transform and keyframes, the fifteen filters, undo, canvas selection
/// and the inspector without any of them knowing scripts exist. A script under
/// a Grid, glowing, in a loop is composition nobody had to build.
///
/// It exists because a parameter set has a ceiling that code does not. "Stop at
/// a position, then rotate each particle separately, then leave differently" is
/// three phases with independent per-particle rules and access to the particle's
/// index — no arrangement of sliders expresses that, and every effect added to
/// chase it makes the next one no closer.
public struct ScriptEffect: Effect {
    public init() {}

    /// What a fresh clip starts with.
    ///
    /// Not empty. `EffectDocument.add` builds a node from a descriptor's
    /// defaults and a script's source is not among them, so a new clip would be
    /// a blank box drawing nothing — which reads as broken rather than as
    /// waiting for you. It draws something immediately and shows the shape of
    /// the API by doing so.
    public static let starterTemplate = """
    // A script is a clip: it generates over 0...duration in local time, and
    // the timeline moves it. Everything below is yours to change.

    // Declared controls show up in the inspector, and param() reads them.
    params({
      count: { type: 'integer', default: 24, range: [1, 200] },
      radius: { type: 'number', default: 160, range: [10, 400], unit: 'px' },
    })

    const count = param('count')
    const radius = param('radius')

    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2
      const born = (i / count) * duration * 0.5

      sprite(Image.soft)
        .move(Ease.quadOut, born, born + 900,
              320, 240,
              320 + Math.cos(angle) * radius,
              240 + Math.sin(angle) * radius)
        .fade(born, born + 150, 0, 1)
        .fade(born + 700, born + 900, 1, 0)
        .scale(born, born + 900, 0.4, 0.1)
    }
    """

    public static let descriptor: EffectDescriptor = {
        var descriptor = EffectDescriptor(
            type: "script",
            name: "Script",
            category: .generate,
            systemImage: "curlybraces",
            // None of its own. A script's controls are whatever it declares,
            // read per node — see `descriptor(for:)`.
            parameters: [],
        )
        descriptor.initialSource = starterTemplate
        return descriptor
    }()

    /// The controls this particular script declared.
    ///
    /// The reason `Effect.descriptor(for:)` exists. Every effect written by
    /// hand answers the same for every node, so this is the first place the two
    /// paths differ at all: two script clips share one type and one static
    /// descriptor while declaring entirely different parameters.
    public func descriptor(for node: EffectNode) -> EffectDescriptor {
        var resolved = Self.descriptor
        resolved.parameters = node.scriptParameters
        return resolved
    }

    public func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        // The seed comes from the node rather than from the generator handed in
        // here: the script's own random stream has to restart at the same place
        // on every evaluation, and a generator that other code has already
        // drawn from would not.
        let outcome = ScriptRuntime.sprites(for: ScriptRuntime.Request(
            nodeID: context.node.id,
            idPrefix: context.idPrefix,
            source: context.node.scriptSource ?? "",
            values: context.node.values,
            duration: context.duration,
            seed: context.node.seed,
        ))

        // Recorded rather than returned. `evaluate` cannot throw by protocol,
        // and a broken script has to come back as an empty clip rather than as
        // a failure that stops the rest of the document evaluating — so what it
        // had to say travels in a ledger the UI reads after the pass lands.
        ScriptRuntime.record(
            ScriptRuntime.Report(
                diagnostics: outcome.diagnostics,
                logs: outcome.logs,
                // Only when they changed, so the shell is not asked to write
                // the same list back on every keystroke.
                declared: outcome.declared == context.node.scriptParameters
                    ? nil
                    : outcome.declared,
            ),
            for: context.node.id,
        )

        return outcome.sprites
    }
}
