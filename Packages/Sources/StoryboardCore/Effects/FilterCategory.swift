import Foundation

/// How the Filters tab is grouped: by what a filter does to a clip.
///
/// Its own list rather than `LibraryCategory`: the Effects tab groups things
/// that generate, and a filter transforms. Sharing one enum made nine filters
/// pile up in "Stylise" and left the panel with a single useful distinction.
///
/// Closed, so a category nobody can misspell is one the panel can rely on.
/// `threeD` is declared before anything lives in it — the panel hides empty
/// categories, so it costs nothing until the first filter arrives.
public enum FilterCategory: String, CaseIterable, Sendable, Codable {
    /// Changes how the clip looks.
    case look = "Look"
    /// Adds light, or its absence.
    case light = "Light"
    /// Adds or reshapes movement.
    case motion = "Motion"
    /// Depth tricks. Empty for now.
    case threeD = "3D"
    /// Copies what is there.
    case repetition = "Repeat"
    /// Breaks the picture on purpose.
    case destroy = "Destroy"
    /// Changes when things happen.
    case time = "Time"
    /// Listens to the song.
    case audio = "Audio"

    /// The order they appear in, declared rather than alphabetical.
    public static let displayOrder: [FilterCategory] = [
        .look, .light, .motion, .threeD, .repetition, .destroy, .time, .audio,
    ]

    public var systemImage: String {
        switch self {
        case .look: "camera.filters"
        case .light: "sun.max"
        case .motion: "point.topleft.down.to.point.bottomright.curvepath"
        case .threeD: "cube"
        case .repetition: "square.grid.2x2"
        case .destroy: "burst"
        case .time: "clock.arrow.circlepath"
        case .audio: "waveform"
        }
    }
}

extension FilterCategory: DisplayOrdered {}

public extension FilterCategory {
    /// The chips to show: categories with at least one filter, in declared order.
    ///
    /// Computed from the **whole** library, never from a search result — a row
    /// that reshuffles as you type is a row you cannot aim at.
    static func visibleChips(in library: [FilterDescriptor]) -> [FilterCategory] {
        displayOrder.filter { category in library.contains { $0.category == category } }
    }

    /// The filters the grid shows.
    ///
    /// A query **overrides** the chip rather than combining with it: someone
    /// typing "glow" with Look selected wants Glow, not an empty grid that
    /// makes them think it does not exist. Clearing the query gives the chip
    /// back, since the selection is kept.
    static func visible(
        in library: [FilterDescriptor],
        chip: FilterCategory?,
        query: String,
    ) -> [FilterDescriptor] {
        guard query.isEmpty else {
            let needle = query.lowercased()
            return library.filter {
                $0.name.lowercased().contains(needle)
                    || $0.category.rawValue.lowercased().contains(needle)
            }
        }
        guard let chip else { return library }
        return library.filter { $0.category == chip }
    }
}
