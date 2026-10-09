/// The tabs a selected clip's inspector is split into.
///
/// One thing at a time instead of one long scroll: an emitter alone has thirty
/// parameters, and with its timing, transform and filters stacked above and
/// below them the panel was a column to scroll through rather than a place to
/// find something. Each tab answers one question about the clip.
public enum InspectorTab: String, CaseIterable, Identifiable, Sendable {
    /// What it draws: the effect's own parameters, and a compound's layers.
    case effect
    /// When and where it is: timing, alignment and transform — what every clip
    /// has, whatever it draws.
    case clip
    /// How it looks: the filters on it.
    case filters
    /// What its last run printed and where it failed — script clips only.
    case output

    public var id: Self { self }

    public var title: String {
        switch self {
        case .effect: "Effect"
        case .clip: "Clip"
        case .filters: "Filters"
        case .output: "Output"
        }
    }

    public var systemImage: String {
        switch self {
        case .effect: "wand.and.stars"
        case .clip: "move.3d"
        case .filters: "camera.filters"
        case .output: "text.alignleft"
        }
    }

    /// The tabs a clip has: every clip the first three, a script clip its
    /// output as well. A tab that is always there and empty for nine clips out
    /// of ten is a tab that teaches people to stop looking at it.
    ///
    /// A clip that draws nothing — a sound — has no look to filter, so it keeps
    /// the file and its timing and nothing else.
    public static func tabs(isScript: Bool, drawsSprites: Bool = true) -> [InspectorTab] {
        guard drawsSprites else { return [.effect, .clip] }
        return isScript ? [.effect, .clip, .filters, .output] : [.effect, .clip, .filters]
    }

    /// The tab to show for a clip, given the one that was chosen.
    ///
    /// The choice itself is kept: someone reading a script's output who picks
    /// an emitter for a moment and comes back finds the output still open,
    /// rather than having been sent to Effect for good.
    public func shown(isScript: Bool, drawsSprites: Bool = true) -> InspectorTab {
        Self.tabs(isScript: isScript, drawsSprites: drawsSprites).contains(self) ? self : .effect
    }
}
