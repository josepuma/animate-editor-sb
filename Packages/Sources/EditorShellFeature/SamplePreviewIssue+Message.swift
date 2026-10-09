import StoryboardCore

extension SamplePreviewIssue {
    /// What the inspector tells the author, one sentence per cause. Kept in one
    /// place so the badge's tooltip and the warning cannot drift apart.
    var message: String {
        switch self {
        case .empty: "This file has no audio."
        case .tooLong: "Too long to preview (over 60 s). It's still exported."
        case .missing: "File not found in the beatmap folder."
        case .undecodable: "This Mac can't decode this file. It's still exported."
        }
    }
}
