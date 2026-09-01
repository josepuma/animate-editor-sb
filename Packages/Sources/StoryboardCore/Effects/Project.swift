import Foundation

/// A saved storyboard project.
///
/// What is stored is the **document** — the effects placed, their parameters,
/// their keyframes — and never the sprites those produce. Sprites are derived
/// on every evaluation, so saving them would be saving an answer whose question
/// is right there beside it, and the two would drift the moment anything
/// changed.
///
/// Written as JSON so a project can be read, diffed and repaired by hand. A
/// binary format is faster to parse and useless when something goes wrong: a
/// file nobody can open is a file nobody can fix.
public struct Project: Codable, Sendable {
    /// What version of this format the file was written with.
    ///
    /// Present from the first release, because the alternative is guessing
    /// later: a file with no version cannot be told apart from one written by
    /// a version that had not thought about versions yet.
    public var formatVersion: Int
    public var document: EffectDocument

    /// Where the timeline was looking when the project was saved.
    ///
    /// Part of the project rather than of the app's preferences: it belongs to
    /// this storyboard, and reopening one to find the view somewhere else means
    /// finding your place again every time. Optional, so a file written before
    /// this opens showing the whole track as it always did.
    public var view: TimelineView?

    /// The version this build writes.
    public static let currentVersion = 1

    /// The oldest version this build can still read.
    public static let minimumReadableVersion = 1

    /// The timeline's window, saved with the project.
    public struct TimelineView: Codable, Sendable, Equatable {
        /// How far in the view was zoomed.
        public var magnification: Double
        /// Where the window began, in milliseconds.
        public var start: Double

        public init(magnification: Double, start: Double) {
            self.magnification = magnification
            self.start = start
        }
    }

    public init(
        document: EffectDocument,
        view: TimelineView? = nil,
        formatVersion: Int = Project.currentVersion,
    ) {
        self.formatVersion = formatVersion
        self.document = document
        self.view = view
    }
}

/// Reading and writing project files.
public enum ProjectFile {
    /// What a project is called inside a beatmap folder.
    ///
    /// Beside the `.osu` files rather than in an application-support directory,
    /// so the project travels with the beatmap: copied, moved or shared, it
    /// arrives whole. osu! ignores an extension it does not know.
    public static let name = "storyboard.aesb"

    /// The project file for a beatmap folder.
    public static func url(inFolder folder: URL) -> URL {
        folder.appending(path: name)
    }

    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted and indented: a project lives beside the beatmap and will end
        // up in someone's version control, where a diff that reorders itself
        // every save is a diff nobody reads.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    public static func decode(_ data: Data) throws -> Project {
        let project = try JSONDecoder().decode(Project.self, from: data)

        guard project.formatVersion >= Project.minimumReadableVersion else {
            throw ProjectError.tooOld(project.formatVersion)
        }
        guard project.formatVersion <= Project.currentVersion else {
            throw ProjectError.tooNew(project.formatVersion)
        }
        return project
    }

    /// Writes a project into a beatmap folder.
    ///
    /// Written to a neighbouring file and then moved into place. A save
    /// interrupted halfway leaves the previous project intact rather than a
    /// truncated one — and a truncated project is a lost project.
    public static func write(_ project: Project, toFolder folder: URL) throws {
        let data = try encode(project)
        let destination = url(inFolder: folder)
        let temporary = folder.appending(path: ".\(name).saving")

        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    }

    /// Reads a project from a beatmap folder, or `nil` when there is none.
    ///
    /// A missing file is not an error: most folders have never been opened in
    /// this editor, and that is the ordinary case rather than a failure.
    public static func read(fromFolder folder: URL) throws -> Project? {
        let source = url(inFolder: folder)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        return try decode(Data(contentsOf: source))
    }

    public static func exists(inFolder folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(inFolder: folder).path)
    }
}

public enum ProjectError: Error, CustomStringConvertible, Equatable {
    case tooOld(Int)
    case tooNew(Int)

    public var description: String {
        switch self {
        case let .tooOld(version):
            "This project was written by a version too old to read (format \(version))."
        case let .tooNew(version):
            "This project was written by a newer version of the app (format \(version))."
        }
    }
}
