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

    public var id: Self { self }

    public var title: String {
        switch self {
        case .effect: "Effect"
        case .clip: "Clip"
        case .filters: "Filters"
        }
    }

    public var systemImage: String {
        switch self {
        case .effect: "wand.and.stars"
        case .clip: "move.3d"
        case .filters: "camera.filters"
        }
    }
}
