import Foundation

/// Undo and redo, as snapshots of the whole document.
///
/// Snapshots rather than inverse operations, and deliberately so: an undo stack
/// built from "the opposite of what just happened" needs an inverse written for
/// every edit, and the day someone adds an edit and forgets its inverse is the
/// day undo starts corrupting documents quietly. A copy of the document cannot
/// be wrong about what it restores.
///
/// It is affordable because the document is **intent**, not output — nodes and
/// their parameters, never the sprites they derive. Measured on a deliberately
/// overloaded project, fifty-six compound nodes with filters came to 300 KB;
/// the sprites those same nodes evaluate to are tens of megabytes.
public struct EditHistory: Sendable {
    /// Past states, oldest first. The present is not in here.
    private var past: [EffectDocument] = []
    private var future: [EffectDocument] = []

    /// Far more than anyone walks back, and still a bounded amount of memory.
    public let limit: Int

    public init(limit: Int = 60) {
        self.limit = limit
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Records the state **before** an edit.
    ///
    /// Called with the document as it stands, immediately before it changes:
    /// undo restores what was there, so what is captured is the past, not the
    /// result. Recording afterwards would leave the first undo doing nothing.
    public mutating func record(_ document: EffectDocument) {
        past.append(document)
        if past.count > limit { past.removeFirst(past.count - limit) }

        // A new edit invalidates the branch that was undone away — the same
        // rule every editor follows, because the alternative is a tree nobody
        // asked for and nobody can see.
        future.removeAll(keepingCapacity: true)
    }

    /// Steps back, given where the document is now.
    ///
    /// The present is handed in rather than stored, so the history never holds
    /// a stale copy of a document that has moved on without it.
    public mutating func undo(from current: EffectDocument) -> EffectDocument? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(from current: EffectDocument) -> EffectDocument? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    /// Forgets everything, for when the document is replaced wholesale.
    ///
    /// Opening another project has to clear this: undoing into the previous
    /// beatmap's document would restore effects that belong to a different map,
    /// which is worse than having no undo at all.
    public mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
