import Foundation

/// A lane of the timeline: a name, a layer, and the effects placed along it.
///
/// A track holds many effects rather than being one, which is what lets a
/// project stay readable as it grows. One row per effect turns a storyboard
/// with thirty of them into thirty rows nobody can scan, and leaves no way to
/// say that these four belong together.
///
/// The layer lives here rather than on each effect: osu!'s layers are about
/// what draws in front of what, which is the same question a track answers.
public struct EffectTrack: Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var layer: Layer
    public var nodes: [EffectNode]
    public var isVisible: Bool
    public var isLocked: Bool

    public init(
        id: String,
        name: String,
        layer: Layer = .foreground,
        nodes: [EffectNode] = [],
        isVisible: Bool = true,
        isLocked: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.layer = layer
        self.nodes = nodes
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    /// The span from the earliest effect to the latest, or `nil` when empty.
    public var timeRange: ClosedRange<Double>? {
        guard let first = nodes.first else { return nil }
        let lower = nodes.reduce(first.startTime) { min($0, $1.startTime) }
        let upper = nodes.reduce(first.endTime) { max($0, $1.endTime) }
        return lower...max(lower, upper)
    }
}

/// The placed effects that make up a storyboard, grouped into tracks.
///
/// This is what a project saves. The sprites are derived from it on every
/// evaluation and never stored — keeping the output instead would leave
/// thousands of loose commands with no way back to the emitter that wrote them.
public struct EffectDocument: Sendable {
    public var tracks: [EffectTrack]

    public init(tracks: [EffectTrack] = []) {
        self.tracks = tracks
    }

    // ─── Reading ─────────────────────────────────────────────────────────────

    /// Every placed effect, in draw order.
    ///
    /// Track order is draw order within a layer: the renderer sorts by layer
    /// and keeps array order to break ties, so a track later in this list draws
    /// in front of one before it.
    public var nodes: [EffectNode] {
        tracks.flatMap(\.nodes)
    }

    public subscript(id: EffectNode.ID) -> EffectNode? {
        get {
            for track in tracks {
                if let node = track.nodes.first(where: { $0.id == id }) { return node }
            }
            return nil
        }
        set {
            guard let location = locate(id) else { return }
            guard let newValue else {
                tracks[location.track].nodes.remove(at: location.node)
                return
            }
            tracks[location.track].nodes[location.node] = newValue
        }
    }

    public func track(id: EffectTrack.ID) -> EffectTrack? {
        tracks.first { $0.id == id }
    }

    /// Which track a node lives on.
    public func trackID(of nodeID: EffectNode.ID) -> EffectTrack.ID? {
        locate(nodeID).map { tracks[$0.track].id }
    }

    /// Whether a track is effectively editable — a locked one is not.
    public func isEditable(_ trackID: EffectTrack.ID) -> Bool {
        track(id: trackID).map { !$0.isLocked } ?? false
    }

    private func locate(_ nodeID: EffectNode.ID) -> (track: Int, node: Int)? {
        for (trackIndex, track) in tracks.enumerated() {
            if let nodeIndex = track.nodes.firstIndex(where: { $0.id == nodeID }) {
                return (trackIndex, nodeIndex)
            }
        }
        return nil
    }

    // ─── Tracks ──────────────────────────────────────────────────────────────

    /// Adds an empty track and returns it.
    @discardableResult
    public mutating func addTrack(named name: String? = nil, layer: Layer = .foreground) -> EffectTrack {
        let track = EffectTrack(
            id: "track-\(UUID().uuidString.prefix(8))",
            name: name ?? "Track \(tracks.count + 1)",
            layer: layer,
        )
        tracks.append(track)
        return track
    }

    public mutating func removeTrack(_ trackID: EffectTrack.ID) {
        tracks.removeAll { $0.id == trackID }
    }

    public mutating func rename(_ trackID: EffectTrack.ID, to name: String) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // An empty name would leave a nameless row that cannot be clicked to
        // rename again, since there is nothing left to click.
        guard !trimmed.isEmpty else { return }
        tracks[index].name = trimmed
    }

    public mutating func setLayer(_ layer: Layer, on trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].layer = layer
    }

    public mutating func toggleVisibility(of trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isVisible.toggle()
    }

    public mutating func toggleLock(of trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isLocked.toggle()
    }

    /// Moves a track one step later in the draw order, so it draws in front.
    ///
    /// Layer still wins — a Background track cannot be raised above a
    /// Foreground one, which is osu!'s rule rather than this editor's.
    public mutating func raiseTrack(_ trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              index < tracks.count - 1
        else { return }
        tracks.swapAt(index, index + 1)
    }

    public mutating func lowerTrack(_ trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }), index > 0 else { return }
        tracks.swapAt(index, index - 1)
    }

    public func canRaiseTrack(_ trackID: EffectTrack.ID) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        return index < tracks.count - 1
    }

    public func canLowerTrack(_ trackID: EffectTrack.ID) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        return index > 0
    }

    // ─── Effects ─────────────────────────────────────────────────────────────

    /// Adds an effect to a track, opening one when there is nowhere to put it.
    ///
    /// Tracks appear as they are needed rather than being created by hand:
    /// making an empty row before anything can go in it is friction in the way
    /// of the thing someone actually asked for.
    @discardableResult
    public mutating func add(
        _ descriptor: EffectDescriptor,
        at startTime: Double,
        duration: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode {
        let index = trackIndex(preferring: trackID)

        let sameType = nodes.filter { $0.type == descriptor.type }.count
        let node = EffectNode(
            id: "\(descriptor.type)-\(UUID().uuidString.prefix(8))",
            type: descriptor.type,
            name: sameType == 0 ? descriptor.name : "\(descriptor.name) \(sameType + 1)",
            layer: tracks[index].layer,
            startTime: startTime,
            duration: duration,
            // Seeded from how many effects are already placed, so two emitters
            // dropped with the same settings do not come out as one field drawn
            // twice.
            seed: UInt64(nodes.count &+ 1) &* 0x9E37_79B9,
            values: descriptor.defaultValues,
        )
        tracks[index].nodes.append(node)
        return node
    }

    /// Where a new effect goes: the track asked for, the last one, or a fresh
    /// one when the document is empty.
    private mutating func trackIndex(preferring trackID: EffectTrack.ID?) -> Int {
        if let trackID, let index = tracks.firstIndex(where: { $0.id == trackID }) {
            return index
        }
        if tracks.isEmpty {
            addTrack(named: "Effects")
        }
        return tracks.count - 1
    }

    /// Changes one parameter on one effect.
    public mutating func setValue(_ value: EffectValue, for parameterID: String, on nodeID: EffectNode.ID) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].values[parameterID] = value
    }

    /// Moves an effect along its track without changing how long it runs.
    ///
    /// Clamped at zero: a storyboard can open before the audio does, but a
    /// negative start would be dragged past the left edge of the timeline with
    /// no way to grab it back.
    public mutating func move(_ nodeID: EffectNode.ID, to startTime: Double) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].startTime = max(0, startTime)
    }

    /// Moves an effect to another track, keeping its position in time.
    ///
    /// The effect takes on the destination's layer: the layer is a property of
    /// the lane, and a node carrying its old one would draw in a place its row
    /// does not claim.
    public mutating func move(_ nodeID: EffectNode.ID, toTrack trackID: EffectTrack.ID) {
        guard let from = locate(nodeID),
              let to = tracks.firstIndex(where: { $0.id == trackID }),
              from.track != to
        else { return }

        var node = tracks[from.track].nodes.remove(at: from.node)
        node.layer = tracks[to].layer
        tracks[to].nodes.append(node)
    }

    /// Resizes an effect from one edge, keeping the other where it is.
    public mutating func resize(
        _ nodeID: EffectNode.ID,
        startTime: Double,
        duration: Double,
        minimumDuration: Double = 100,
    ) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].startTime = max(0, startTime)
        tracks[location.track].nodes[location.node].duration = max(minimumDuration, duration)
    }

    public mutating func remove(_ nodeID: EffectNode.ID) {
        self[nodeID] = nil
    }

    /// The span every placed effect covers, or `nil` when nothing is placed.
    public var timeRange: ClosedRange<Double>? {
        let placed = nodes
        guard let first = placed.first else { return nil }
        let lower = placed.reduce(first.startTime) { min($0, $1.startTime) }
        let upper = placed.reduce(first.endTime) { max($0, $1.endTime) }
        return lower...max(lower, upper)
    }
}
