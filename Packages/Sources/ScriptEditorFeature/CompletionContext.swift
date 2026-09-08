import Foundation

/// What the author is in the middle of typing.
///
/// Pure text in, an answer out — no editor, no async, nothing to mock. The
/// context is the part that decides whether completion helps or gets in the
/// way: a list of every global offered after `Image.` is a list where the one
/// useful answer is buried, and offering nothing after `sprite(Image.soft).`
/// is the moment somebody needed it most.
enum CompletionContext: Equatable {
    /// After `Something.`, wanting that namespace's members.
    case members(of: String, prefix: String)
    /// After a `)`or a chained call, wanting a sprite's methods.
    case spriteMethod(prefix: String)
    /// A bare identifier, wanting globals.
    case global(prefix: String)
    /// Nowhere useful — inside a string, a comment, or a number.
    case none

    /// Reads the context at `location` in `text`.
    ///
    /// - Parameter location: a UTF-16 offset, which is what the editor reports.
    static func at(_ location: Int, in text: String) -> CompletionContext {
        guard let cursor = index(at: location, in: text) else { return .none }
        let before = text[text.startIndex..<cursor]

        // Nothing is offered inside a string or a comment. Completing an
        // identifier inside a file path is a popup covering the thing being
        // typed, with nothing in it that could ever be right.
        guard !isInStringOrComment(before) else { return .none }

        let word = trailingWord(before)
        let beforeWord = before[before.startIndex..<before.index(before.endIndex, offsetBy: -word.count)]

        guard beforeWord.last == "." else {
            // A bare word, or nothing. Both want globals — with nothing typed,
            // the list is how somebody finds out what exists at all.
            return .global(prefix: word)
        }

        let receiver = beforeWord[beforeWord.startIndex..<beforeWord.index(before: beforeWord.endIndex)]

        // `Image.`, `Ease.`, `rng.` — a known namespace by name.
        let namespace = trailingWord(receiver)
        if !namespace.isEmpty, !ScriptAPI.members(of: namespace).isEmpty {
            return .members(of: namespace, prefix: word)
        }

        // `sprite(…).` or `…).` or `.fade(…).` — anything whose last token is a
        // closing paren is taken to be a sprite builder. Every call in this API
        // that returns something chainable returns a sprite, so the guess is
        // right whenever it fires, and wrong only by offering sprite methods
        // after some other call — a list with nothing that fits rather than a
        // wrong insertion.
        //
        // Whitespace is skipped, newlines included, because that is how a chain
        // is actually written: `sprite(…)` on one line and `.move(…)` indented
        // beneath it. Reading only the character immediately before the dot
        // missed every multi-line chain, which is most of them.
        if receiver.reversed().first(where: { !$0.isWhitespace }) == ")" {
            return .spriteMethod(prefix: word)
        }

        return .none
    }

    /// The whole word at `location`, and where it starts.
    ///
    /// Reads in both directions, unlike the completion context, which only
    /// looks behind: a cursor hovering `sprite` sits in the middle of the word,
    /// not at its end.
    static func word(at location: Int, in text: String) -> (word: String, range: NSRange)? {
        guard let cursor = index(at: location, in: text) else { return nil }

        func isIdentifier(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }

        var start = cursor
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isIdentifier(text[previous]) else { break }
            start = previous
        }

        var end = cursor
        while end < text.endIndex, isIdentifier(text[end]) {
            end = text.index(after: end)
        }

        guard start < end else { return nil }

        let word = String(text[start..<end])
        let offset = text.utf16.distance(from: text.utf16.startIndex, to: start.samePosition(in: text.utf16)!)
        return (word, NSRange(location: offset, length: word.utf16.count))
    }

    /// The receiver immediately before the word at `location`, if any.
    ///
    /// So `soft` in `Image.soft` is looked up among the images rather than
    /// among the globals, where it does not exist.
    static func receiver(before range: NSRange, in text: String) -> String? {
        guard range.location > 0,
              let dot = index(at: range.location - 1, in: text),
              text[dot] == "."
        else { return nil }

        let namespace = trailingWord(text[text.startIndex..<dot])
        return namespace.isEmpty ? nil : namespace
    }

    // MARK: - Reading backwards

    private static func index(at location: Int, in text: String) -> String.Index? {
        guard location >= 0 else { return nil }
        let utf16 = text.utf16
        guard location <= utf16.count else { return nil }
        return String.Index(utf16Offset: location, in: text)
    }

    /// The identifier characters immediately before the cursor.
    private static func trailingWord(_ text: Substring) -> String {
        String(text.reversed().prefix { character in
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }.reversed())
    }

    /// Whether the cursor sits inside a string or a comment.
    ///
    /// Walked forwards from the start of the line rather than the file: a
    /// string cannot span lines in this language except a template literal, and
    /// scanning a whole document on every keystroke is work done per character
    /// typed.
    ///
    /// A template literal opened on an earlier line is therefore missed, and
    /// completion will offer globals inside it. That is the same class of fault
    /// the regex highlighter already has, and both are cosmetic — a popup that
    /// can be dismissed, not a wrong insertion.
    private static func isInStringOrComment(_ before: Substring) -> Bool {
        let line = before.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""

        var quote: Character?
        var escaped = false
        var previous: Character?

        for character in line {
            if escaped {
                escaped = false
                previous = character
                continue
            }

            if character == "\\", quote != nil {
                escaped = true
                continue
            }

            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" || character == "`" {
                quote = character
            } else if character == "/", previous == "/" {
                // The rest of the line is a comment, so anywhere after this is
                // inside one.
                return true
            }

            previous = character
        }

        return quote != nil
    }
}
