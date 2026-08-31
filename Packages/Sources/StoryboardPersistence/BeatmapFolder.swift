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

            // The editor's own output is not the beatmap's art.
            //
            // An export writes a complete copy of the storyboard's images into
            // this folder — the generated ones *and* the mapper's own. Indexed
            // alongside the originals they compete for the same keys, and since
            // the first match wins, whichever the enumerator reached first
            // became the image the canvas drew. An emitter started rendering
            // the background: `export/` had answered for `glow.png`.
            guard !isExportOutput(relative) else { continue }

            // First match wins, so a folder holding both `SB/a.png` and
            // `sb/a.png` resolves deterministically by enumeration order.
            let key = relative.lowercased()
            if index[key] == nil { index[key] = fileURL }
        }

        return index
    }

    /// Whether a path is inside the folder an export writes to.
    private static func isExportOutput(_ relative: String) -> Bool {
        let lowered = relative.lowercased()
        return lowered == exportFolderName || lowered.hasPrefix(exportFolderName + "/")
    }

    /// The folder `StoryboardExport` writes into, named here as well because
    /// persistence cannot import the renderer. A test keeps the two in step.
    public static let exportFolderName = "export"

    // ─── Lookup ──────────────────────────────────────────────────────────────

    /// Resolves a storyboard-relative path to a file on disk.
    ///
    /// Backslashes are treated as separators and casing is ignored, matching
    /// how osu! itself resolves these paths.
    public func fileURL(forRelativePath path: String) -> URL? {
        let normalised = Self.normalise(path)
        guard !normalised.isEmpty else { return nil }
        // Checked on both routes: the on-disk fallback below would otherwise
        // walk straight into the export folder the index just excluded.
        guard !Self.isExportOutput(normalised) else { return nil }
        if let known = filesByLowercasedPath[normalised] { return known }
        return resolveOnDisk(normalised)
    }

    /// Looks for one file the index does not know about.
    ///
    /// The index is a snapshot taken when the folder was opened, which is right
    /// for reading a finished storyboard and wrong for editing one: dropping an
    /// image into `sb/` while the editor runs is the ordinary way to add an
    /// asset, and without this the file does not exist as far as the app is
    /// concerned until the project is reopened.
    ///
    /// A miss checks that one path rather than walking the folder again. A
    /// beatmap carries hundreds of files, and re-indexing all of them to find
    /// one is work proportional to the wrong thing — and it would run on every
    /// genuinely missing path, which is exactly the case a storyboard with a
    /// typo hits on every sprite.
    private func resolveOnDisk(_ normalisedPath: String) -> URL? {
        let candidate = url.appending(path: normalisedPath, directoryHint: .notDirectory)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }

        // The index is case-insensitive because osu! storyboards are written
        // against filenames on a case-insensitive filesystem; this check is
        // not, so only an exact match is found here. That is the common case —
        // a file just added, named as the storyboard spells it.
        return candidate
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
    /// The folder holds nothing to build a storyboard against — no difficulty,
    /// no audio, no `.osb`.
    ///
    /// An *empty* storyboard is not an error: a folder with audio and a
    /// difficulty is where a new storyboard starts.
    case notABeatmapFolder(String)

    public var description: String {
        switch self {
        case let .notFound(url):
            "No folder at \(url.path)."
        case let .notADirectory(url):
            "\(url.lastPathComponent) is a file, not a folder."
        case let .notABeatmapFolder(name):
            "\(name) has no .osu difficulty and no audio file."
        }
    }
}
