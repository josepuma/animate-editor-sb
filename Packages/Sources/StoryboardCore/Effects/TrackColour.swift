import Foundation

/// A colour a track can be given, from a fixed set.
///
/// Named rather than free-form: a track colour is a label people sort by at a
/// glance, and an arbitrary picker produces near-identical shades that defeat
/// that. Seven distinguishable ones are more useful than sixteen million.
///
/// In Core because the choice is saved with the project, and Core is what
/// writes it. What each name looks like belongs to the design system.
public enum TrackColour: String, CaseIterable, Sendable, Codable {
    case blue, violet, pink, teal, amber, green, red

    public var title: String {
        switch self {
        case .blue: "Blue"
        case .violet: "Violet"
        case .pink: "Pink"
        case .teal: "Teal"
        case .amber: "Amber"
        case .green: "Green"
        case .red: "Red"
        }
    }
}
