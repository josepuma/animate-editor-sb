import Combine
import DesignSystem
import LanguageSupport
import SwiftUI

/// Answers the editor's questions about a storyboard script.
///
/// The editor already draws the completion list, navigates it and inserts what
/// is chosen — all that was missing was something to say *what* to offer. For a
/// closed API that is a table lookup, not a language server: there are no types
/// to infer and no modules to resolve.
///
/// Most of `LanguageService` is left inert on purpose. Diagnostics arrive from
/// the evaluator rather than from parsing here, and semantic tokens would be a
/// second highlighter disagreeing with the first.
/// Not `@MainActor`: the protocol's own requirements pass non-`Sendable` values
/// (`LocationService`, `Completions`), so an isolated conformance cannot satisfy
/// them. The document is guarded by a lock instead — the editor calls this from
/// whichever context it happens to be on, and the two things it holds are one
/// string and one flag.
final class ScriptLanguageService: LanguageService, @unchecked Sendable {
    private let lock = NSLock()
    private var storedText = ""

    /// The document, as last reported by the editor.
    private var text: String {
        get { lock.withLock { storedText } }
        set { lock.withLock { storedText = newValue } }
    }

    // MARK: - Document synchronisation

    private var storedIsOpen = false
    var isOpen: Bool { lock.withLock { storedIsOpen } }

    func openDocument(with text: String, locationService _: LocationService) async throws {
        lock.withLock {
            storedText = text
            storedIsOpen = true
        }
    }

    func documentDidChange(
        position changeLocation: Int,
        changeInLength delta: Int,
        lineChange _: Int,
        columnChange _: Int,
        newText: String,
    ) async throws {
        // The edited range is spliced rather than the document re-read, because
        // this is called on every keystroke.
        lock.withLock {
            let utf16 = storedText.utf16
            guard changeLocation >= 0, changeLocation <= utf16.count else { return }

            let removed = max(0, newText.utf16.count - delta)
            let start = String.Index(utf16Offset: changeLocation, in: storedText)
            let end = String.Index(
                utf16Offset: min(utf16.count, changeLocation + removed),
                in: storedText,
            )
            storedText.replaceSubrange(start..<end, with: newText)
        }
    }

    func closeDocument() async throws {
        lock.withLock {
            storedIsOpen = false
            storedText = ""
        }
    }

    // MARK: - What the editor watches

    let events = PassthroughSubject<LanguageServiceEvent, Never>()

    /// Empty, deliberately.
    ///
    /// A script's problems are found by *running* it, and the evaluator already
    /// reports them — they reach the editor through `ScriptCodeEditor`'s own
    /// `messages` binding. Parsing here to find them again would be a second
    /// opinion that can disagree with the one that matters.
    let diagnostics = CurrentValueSubject<Set<TextLocated<Message>>, Never>([])

    /// A dot opens the list without asking.
    ///
    /// The one keystroke where the useful answer is never what somebody was
    /// about to type: after `Image.` there are seven possibilities and no way
    /// to guess which. Letters do not trigger it — a popup on every character
    /// is a popup in the way.
    let completionTriggerCharacters = CurrentValueSubject<[Character], Never>(["."])

    let extraActions = CurrentValueSubject<[ExtraAction], Never>([])

    // MARK: - Completion

    func completions(at location: Int, reason _: CompletionTriggerReason) async throws -> Completions {
        let context = CompletionContext.at(location, in: text)

        let entries: [ScriptAPI.Entry] = switch context {
        case let .members(namespace, prefix):
            ScriptAPI.members(of: namespace).matching(prefix)
        case let .spriteMethod(prefix):
            ScriptAPI.spriteMethods.matching(prefix)
        case let .global(prefix):
            // Only once something is typed. Every global offered on an empty
            // line is a popup that appears while somebody is thinking, and the
            // way to dismiss it is to type past it.
            //
            // The script's own names come first: `count`, declared on the line
            // above, is far likelier to be what somebody is reaching for than
            // anything the host provides — and it was not offered at all while
            // `duration` was, which is backwards.
            prefix.isEmpty ? [] : declared(matching: prefix) + ScriptAPI.globals.matching(prefix)
        case .none:
            []
        }

        return Completions(
            isIncomplete: false,
            items: entries.enumerated().map { index, entry in
                let insert = insertion(for: entry, at: location, in: context)
                return completion(
                    entry,
                    id: index,
                    selected: index == 0,
                    insertText: insert.text,
                    replacing: insert.range,
                )
            },
        )
    }

    /// What the script itself declared, as completion entries.
    ///
    /// The prefix is excluded from its own suggestions: offering `count` while
    /// the caret sits in the middle of typing `count` is a list whose only
    /// entry is what is already there.
    private func declared(matching prefix: String) -> [ScriptAPI.Entry] {
        ScriptDeclarations.all(in: text)
            .filter { $0.name != prefix && $0.name.lowercased().hasPrefix(prefix.lowercased()) }
            .map { declaration in
                ScriptAPI.Entry(
                    name: declaration.name,
                    summary: "\(declaration.keyword) — line \(declaration.line)",
                    kind: declaration.keyword == "function" ? .function : .value,
                )
            }
    }

    /// The characters the chosen completion replaces, and what replaces them.
    ///
    /// Only ever the word typed — never the receiver.
    ///
    /// It replaced `Ease.quadOut` whole for a while, because `NSTextView`
    /// counts the dot as part of a word: with the caret after `Ease.out` its
    /// `rangeForUserCompletion` reports all eight characters, measured. That
    /// range is only the *fallback* though (`CodeActions.swift:242` passes mine
    /// when it exists), so carrying the receiver was solving a problem that
    /// only appears when the range is `nil` — and it created two: the receiver
    /// was rewritten, so `Ease` lost its keyword colour, and a single
    /// backspace took the whole thing away because one programmatic insertion
    /// is one undo group.
    ///
    /// A range is therefore **always** returned, even for an empty prefix — an
    /// empty range at the caret, which inserts without replacing and never
    /// falls through to the editor's own idea of the word.
    private func insertion(
        for entry: ScriptAPI.Entry,
        at location: Int,
        in context: CompletionContext,
    ) -> (text: String, range: NSRange?) {
        let prefix = switch context {
        case let .members(_, prefix): prefix
        case let .spriteMethod(prefix): prefix
        case let .global(prefix): prefix
        case .none: ""
        }

        return (
            entry.insert,
            NSRange(location: location - prefix.utf16.count, length: prefix.utf16.count)
        )
    }

    private func completion(
        _ entry: ScriptAPI.Entry,
        id: Int,
        selected: Bool,
        insertText: String,
        replacing: NSRange?,
    ) -> Completions.Completion {
        Completions.Completion(
            id: id,
            rowView: { _ in CompletionRow(entry: entry) },
            documentationView: CompletionDocumentation(entry: entry),
            selected: selected,
            sortText: entry.name,
            filterText: entry.name,
            insertText: insertText,
            insertRange: replacing,
            // A dot commits, so `Image.so` + `.` lands `Image.soft.` — which is
            // what a chain wants. A paren does not: it is already in
            // `insertText` for anything callable, and committing on it would
            // double them.
            commitCharacters: ["."],
            refine: { nil },
        )
    }

    // MARK: - Inert

    /// Nothing, and not for want of trying.
    ///
    /// Semantic tokens would be a second highlighter running beside the
    /// regex-based one, and two highlighters that disagree colour the same word
    /// two ways depending on which answered last.
    func tokens(for _: Range<Int>) async throws
        -> [[(token: LanguageConfiguration.Token, range: NSRange)]] { [] }

    // MARK: - Hover

    /// What the name under the cursor is.
    ///
    /// The same table the completion list reads, so a name described here is a
    /// name that exists — and it answers the question completion cannot: what
    /// something does once it is already written, which is most of the time
    /// somebody spends looking at code.
    ///
    /// The receiver matters: `soft` is looked up among the images rather than
    /// among the globals, where it is not. Without that, `Image.soft` would
    /// report nothing while `sprite` reported fine.
    func info(at location: Int) async throws -> (view: any View, anchor: NSRange?)? {
        let document = text
        guard let (word, range) = CompletionContext.word(at: location, in: document) else {
            return nil
        }

        let candidates = if let receiver = CompletionContext.receiver(before: range, in: document) {
            ScriptAPI.members(of: receiver)
        } else {
            ScriptAPI.globals + ScriptAPI.spriteMethods
        }

        if let entry = candidates.first(where: { $0.name == word }) {
            return (view: HoverInfo(entry: entry), anchor: range)
        }

        // Then the script's own names. A scan cannot say what *type* something
        // is — that needs evaluation, and this runs on every hover — so it
        // says what it honestly knows: which keyword introduced it and where.
        // "const, line 4" is the answer to "where does this come from", which
        // is the question somebody hovering a variable actually has.
        guard CompletionContext.receiver(before: range, in: document) == nil,
              let declaration = ScriptDeclarations.all(in: document).first(where: { $0.name == word })
        else { return nil }

        return (
            view: HoverInfo(entry: ScriptAPI.Entry(
                name: declaration.name,
                summary: "\(declaration.keyword) — declared on line \(declaration.line)",
                kind: declaration.keyword == "function" ? .function : .value,
            )),
            anchor: range
        )
    }

    func capabilities() async throws -> (any View)? { nil }
}

private extension [ScriptAPI.Entry] {
    /// The entries a prefix could become.
    ///
    /// Case-insensitive, because nobody reaching for `Image.Soft` means
    /// something else — and matched on the *start* rather than anywhere in the
    /// name: a substring match on "in" offers half the easing table, which is a
    /// list where the answer is buried.
    func matching(_ prefix: String) -> [ScriptAPI.Entry] {
        guard !prefix.isEmpty else { return self }
        return filter { $0.name.lowercased().hasPrefix(prefix.lowercased()) }
    }
}

/// The documentation pane beside the completion list.
///
/// The library reserves it a hundred points whether or not there is anything to
/// show, so the signature alone — already in the row beside the name — spends
/// that space saying the same thing twice. An example answers what a signature
/// cannot: what those numbers mean in place, which is the question somebody
/// reaching for `scaleVec(…, 854, 80, 854, 80)` actually has.
private struct CompletionDocumentation: View {
    let entry: ScriptAPI.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
            }

            if let example = entry.example {
                Text(example)
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.primary)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.tight)
                    .background(
                        Theme.Fill.well,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small),
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a name is, shown on hover.
private struct HoverInfo: View {
    let entry: ScriptAPI.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(entry.name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.primary)

            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .padding(Theme.Spacing.compact)
    }
}

/// One row of the completion list.
private struct CompletionRow: View {
    let entry: ScriptAPI.Entry

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: symbol)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: Theme.Size.controlTiny / 2)

            Text(entry.name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.primary)

            // The signature beside the name, because that is where somebody
            // finds out the easing argument is optional and the times come
            // before the values.
            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .function, .method: "function"
        case .namespace: "cube"
        case .value: "number"
        case .keyword: "textformat.abc"
        }
    }
}
