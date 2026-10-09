import Foundation

/// Why a sample's sound cannot be heard in the editor preview.
///
/// A reason rather than a flag: "can't preview" on its own sent an author to
/// look at their platform when the file was simply empty. A diagnosis has to
/// name its cause. The export ships the file in every case.
public enum SamplePreviewIssue: Error, Sendable, Equatable {
    /// The file opens but holds no audio frames.
    case empty
    /// Longer than the preview keeps decoded — a song pasted in by mistake.
    case tooLong
    /// The path names nothing in the beatmap folder.
    case missing
    /// This machine cannot open or convert the file.
    case undecodable
}
