import Foundation

/// A beatmap folder on disk, with the case-insensitive path resolution osu!
/// storyboards rely on.
///
/// `.osb` files reference images with paths written on whatever machine
/// authored them: `sb\logo.png` from Windows, `SB/Logo.PNG` with arbitrary
/// casing. osu! resolves those against the real file system regardless, so the
/// same lookups have to work here.
public struct BeatmapFolder: Sendable {
    /// Root directory of the beatmap.
    public let url: URL
    /// Folder name, used as the project's display name.
    public var name: String { url.lastPathComponent }

    /// Every file under the root, keyed by lowercased relative path.
    private let filesByLowercasedPath: [String: URL]

    // ─── Loading ─────────────────────────────────────────────────────────────

    /// Indexes `url` and everything beneath it.
    ///
    /// - Throws: ``BeatmapFolderError`` when the path is missing or is not a
    ///   directory.
    public init(url: URL) throws {
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw BeatmapFolderError.notFound(url)
        }
        guard isDirectory.boolValue else {
            throw BeatmapFolderError.notADirectory(url)
        }

        self.url = url
        filesByLowercasedPath = Self.indexFiles(under: url, using: fileManager)
    }

    private static func indexFiles(under root: URL, using fileManager: FileManager) -> [String: URL] {
        var index: [String: URL] = [:]

        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
        ) else { return index }

        let rootPath = root.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }

            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }

            let relative = String(path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }

            // First match wins, so a folder holding both `SB/a.png` and
            // `sb/a.png` resolves deterministically by enumeration order.
            let key = relative.lowercased()
            if index[key] == nil { index[key] = fileURL }
        }

        return index
    }

    // ─── Lookup ──────────────────────────────────────────────────────────────

    /// Resolves a storyboard-relative path to a file on disk.
    ///
    /// Backslashes are treated as separators and casing is ignored, matching
    /// how osu! itself resolves these paths.
    public func fileURL(forRelativePath path: String) -> URL? {
        let normalised = Self.normalise(path)
        guard !normalised.isEmpty else { return nil }
        return filesByLowercasedPath[normalised]
    }

    /// Reads a storyboard-relative file, or `nil` when it cannot be found.
    public func data(forRelativePath path: String) -> Data? {
        guard let url = fileURL(forRelativePath: path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Relative paths of every file with one of `extensions`, case-insensitive.
    ///
    /// - Parameter extensions: extensions without the dot, e.g. `["osu"]`.
    public func files(withExtensions extensions: [String]) -> [String] {
        let wanted = Set(extensions.map { $0.lowercased() })
        return filesByLowercasedPath.keys
            .filter { path in
                guard let dot = path.lastIndex(of: ".") else { return false }
                return wanted.contains(String(path[path.index(after: dot)...]))
            }
            .sorted()
    }

    /// Total number of indexed files.
    public var fileCount: Int { filesByLowercasedPath.count }

    /// Lowercases the path and converts Windows separators.
    ///
    /// `.` segments are dropped and `..` pops the preceding segment, so
    /// `sb/../sb/logo.png` resolves to `sb/logo.png`. A `..` with nothing left
    /// to pop is discarded rather than climbing out, which keeps a storyboard
    /// confined to its own folder.
    static func normalise(_ path: String) -> String {
        var segments: [Substring] = []

        for segment in path.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty { segments.removeLast() }
            default:
                segments.append(segment)
            }
        }

        return segments.joined(separator: "/").lowercased()
    }
}

// ─── Errors ──────────────────────────────────────────────────────────────────

public enum BeatmapFolderError: Error, CustomStringConvertible, Equatable {
    case notFound(URL)
    case notADirectory(URL)
    case noStoryboardFound(String)

    public var description: String {
        switch self {
        case let .notFound(url):
            "No folder at \(url.path)."
        case let .notADirectory(url):
            "\(url.lastPathComponent) is a file, not a folder."
        case let .noStoryboardFound(name):
            "\(name) contains no .osb file and no .osu file with storyboard events."
        }
    }
}
