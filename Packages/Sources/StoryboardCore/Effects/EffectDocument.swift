import Foundation

/// The placed effects that make up a storyboard, and the operations an editor
/// performs on them.
///
/// This is what a project saves. The sprites are derived from it on every
/// evaluation and never stored — keeping the output instead would leave
/// thousands of loose commands with no way back to the emitter that wrote them.
public struct EffectDocument: Sendable {
    public var nodes: [EffectNode]

    public init(nodes: [EffectNode] = []) {
        self.nodes = nodes
    }

    public subscript(id: EffectNode.ID) -> EffectNode? {
        get { nodes.first { $0.id == id } }
        set {
            guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
            guard let newValue else {
                nodes.remove(at: index)
                return
            }
            nodes[index] = newValue
        }
    }

    /// Adds a node, giving it a name that reads as distinct in the track list.
    ///
    /// Numbering counts existing nodes of the same effect rather than the
    /// document's length, so three emitters read "Emitter 1…3" whatever else is
    /// placed alongside them.
    public mutating func add(
        _ descriptor: EffectDescriptor,
        at startTime: Double,
        duration: Double,
        layer: Layer = .foreground,
    ) -> EffectNode {
        let sameType = nodes.filter { $0.type == descriptor.type }.count
        let node = EffectNode(
            id: "\(descriptor.type)-\(UUID().uuidString.prefix(8))",
            type: descriptor.type,
            name: sameType == 0 ? descriptor.name : "\(descriptor.name) \(sameType + 1)",
            layer: layer,
            startTime: startTime,
            duration: duration,
            // Seeding from the node's place in the document means two emitters
            // dropped with the same settings do not come out as one field drawn
            // twice.
            seed: UInt64(nodes.count &+ 1) &* 0x9E37_79B9,
            values: descriptor.defaultValues,
        )
        nodes.append(node)
        return node
    }

    /// Changes one parameter on one node.
    public mutating func setValue(_ value: EffectValue, for parameterID: String, on nodeID: EffectNode.ID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].values[parameterID] = value
    }

    /// Moves a node without changing how long it runs.
    ///
    /// Clamped at zero: a storyboard can open before the audio does, but a
    /// negative start would be dragged past the left edge of the timeline with
    /// no way to grab it back.
    public mutating func move(_ nodeID: EffectNode.ID, to startTime: Double) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].startTime = max(0, startTime)
    }

    /// Resizes a node from one edge, keeping the other where it is.
    public mutating func resize(
        _ nodeID: EffectNode.ID,
        startTime: Double,
        duration: Double,
        minimumDuration: Double = 100,
    ) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].startTime = max(0, startTime)
        nodes[index].duration = max(minimumDuration, duration)
    }

    /// The span every placed effect covers, or `nil` when nothing is placed.
    public var timeRange: ClosedRange<Double>? {
        guard let first = nodes.first else { return nil }
        let lower = nodes.reduce(first.startTime) { min($0, $1.startTime) }
        let upper = nodes.reduce(first.endTime) { max($0, $1.endTime) }
        return lower...max(lower, upper)
    }
}
