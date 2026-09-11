import Foundation
import StoryboardCore

/// Fills in every script node's source from its file, once per pass.
///
/// `ScriptEffect.evaluate` is synchronous and cannot throw, so it has no way to
/// reach disk — and a seam called from inside it would read a file **per node
/// per evaluation**, which is the shape that has cost this project four
/// separate performance bugs (`spriteCount`, `tail`, `loopSeamSeverity`,
/// `fullRange`: a cache invalidated by the same edit that re-requests it).
///
/// So resolution happens ahead of the work: the document snapshot is resolved
/// on the main actor and the detached evaluation receives nodes that already
/// carry their code. Nothing downstream knows a file was involved.
struct ScriptResolver {
    /// Where the project's script files live.
    private let folder: URL

    /// How a file is read. Injected so a test can count reads and so a
    /// caller can put a cache in front without this type knowing.
    private let load: (ScriptFile, URL) -> String?

    init(folder: URL, load: ((ScriptFile, URL) -> String?)? = nil) {
        self.folder = folder
        self.load = load ?? { file, folder in try? ScriptStore.read(file, inFolder: folder) }
    }

    /// `document` with every script node's source read from its file.
    ///
    /// The file wins over whatever the node carried. A node's `scriptSource` is
    /// a resolved copy, not a second source of truth — and the older key is
    /// still written to the `.aesb`, so preferring it would mean a project
    /// drawing from a snapshot of code that has since been edited elsewhere.
    ///
    /// A file that cannot be read clears the source rather than leaving what
    /// was there. Stale code draws a clip whose file the author has deleted,
    /// which is exactly the silent disagreement between screen and disk that
    /// moving scripts out to files exists to end.
    func resolving(_ document: EffectDocument) -> EffectDocument {
        // Read once per file, not once per node: a file shared by twenty clips
        // is one read, and the whole point of sharing is that they agree.
        var loaded: [ScriptFile: String?] = [:]
        var resolved = document

        for node in document.nodes {
            guard let file = node.scriptFile else { continue }

            let source: String?
            if let cached = loaded[file] {
                source = cached
            } else {
                source = load(file, folder)
                loaded[file] = source
            }

            guard node.scriptSource != source else { continue }
            var updated = node
            updated.scriptSource = source
            resolved[node.id] = updated
        }

        return resolved
    }
}
