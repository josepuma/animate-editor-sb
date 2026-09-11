import Foundation

/// A reference to a script's source file, inside the project folder.
///
/// A single path component, not a relative path. A relative path admits
/// `a/b/../../c`, which then needs canonicalising *and* a descendancy check at
/// every read, every write and every watcher event — three places, one of
/// which gets forgotten. Holding one validated component makes traversal
/// *unrepresentable*: there is no string containing `/` or `..` that survives
/// `init?`, so containment is a property of the type rather than a check
/// someone has to remember to call.
///
/// Scripts live at the project folder's root, beside `storyboard.aesb` — there
/// is deliberately no subfolder support, because the measured `.d.ts`/
/// `jsconfig.json` configuration (a script, the declarations and the config
/// all in one folder) is the configuration that was actually verified to work
/// in VSCode. A subfolder would deviate from what was measured.
public struct ScriptFile: Sendable, Equatable, Hashable {
    /// The file's name inside the project folder, without its extension.
    /// Never a path.
    public let name: String

    /// The longest name allowed, in bytes (not characters — a validated name
    /// must be safe as a filesystem path component on any encoding).
    private static let maximumLength = 255

    /// Validates and constructs a reference, or `nil` for anything unsafe.
    ///
    /// Rejects: empty, `.` or `..`, anything containing a path separator
    /// (`/` or `\`) or a NUL byte, a leading dot (hidden files — and this also
    /// keeps a reference from ever naming `.storyboard.aesb.saving`, the
    /// project's own temp-write file), anything over the length limit, and
    /// anything that is not already its own last path component (which is
    /// what catches every other shape a traversal could take once the
    /// explicit checks above have run).
    public init?(name: String) {
        guard !name.isEmpty else { return nil }
        guard name != ".", name != ".." else { return nil }
        guard !name.contains("/"), !name.contains("\\") else { return nil }
        guard !name.utf8.contains(0) else { return nil }
        guard !name.hasPrefix(".") else { return nil }
        guard name.utf8.count <= Self.maximumLength else { return nil }

        // Structural backstop: a validated name is its own last path
        // component, or something upstream let a traversal shape through.
        let url = URL(fileURLWithPath: name)
        guard url.lastPathComponent == name else { return nil }

        // The extension is stripped rather than refused, because both spellings
        // arrive from places that are right to send them: a migration reads a
        // file name off disk, and a person typing one writes what they see.
        // Stored with it, `fileName` appended a second and the reference named
        // `x.js.js` — a file nothing would ever find.
        var stem = name
        if stem.hasSuffix(Self.fileExtension) {
            stem.removeLast(Self.fileExtension.count)
        }
        // Everything the guards above rejected has to stay rejected after the
        // trim: `.js` on its own is an empty stem, which is not a name.
        guard !stem.isEmpty, stem != "." , stem != ".." else { return nil }

        self.name = stem
    }

    /// The name as it appears on disk. `name` never stores the extension, so
    /// a reference cannot be constructed that already names `.js`, `.osu` or
    /// `storyboard.aesb`.
    public var fileName: String { name + Self.fileExtension }

    /// What a script file is called on disk.
    ///
    /// One constant, because `init?` strips it and `fileName` appends it: two
    /// spellings of the same four characters would let a reference round-trip
    /// into a name nothing can open.
    static let fileExtension = ".js"
}

// MARK: - Codable

extension ScriptFile: Codable {
    /// Decodes as `nil`-equivalent for an unsafe name, never as a thrown
    /// error.
    ///
    /// A throw fails the whole node's decode, which fails the whole
    /// document's decode, which sets `loadFailed` and refuses to save — one
    /// hostile reference in a downloaded `.aesb` would cost the author their
    /// entire project. `EffectNode` reads this field through a `String?`
    /// intermediate and maps it through `init?(name:)`, so an invalid
    /// reference degrades to a clip reporting missing source, not to a
    /// project that will not open.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let name = ScriptFile(name: raw)?.name else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a safe script file name: \(raw)",
            )
        }
        self.name = name
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
