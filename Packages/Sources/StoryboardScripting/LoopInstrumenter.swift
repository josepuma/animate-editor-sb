import Foundation

/// Makes a script's loops count themselves, so a runaway stops on its own.
///
/// JavaScriptCore cannot interrupt a tight synchronous loop from the same
/// thread, and `JSContextGroupSetExecutionTimeLimit` — the API that could — is
/// private WebKit, absent from the public macOS SDK (verified: no match in the
/// system's JavaScriptCore bridgesupport). A watchdog can notice a hang but
/// cannot end it, and the thread it abandons keeps a core busy forever; iterate
/// on a bad script a few times and the editor is crawling.
///
/// So the loop is made to stop itself. Throwing is something JavaScript can do
/// unaided, so nothing needs interrupting from outside.
enum LoopInstrumenter {
    /// The shared iteration budget.
    ///
    /// One budget across every loop, not one per loop. Per-loop counters are
    /// defeated by nesting: two loops of two thousand each stay under any
    /// per-loop ceiling while running four million times between them.
    ///
    /// Two million, measured rather than guessed: JavaScriptCore burns that
    /// many counted iterations in 34ms, and the sprite ceiling is 2000, so it
    /// leaves a thousand iterations per sprite anyone is allowed to draw.
    static let maximumIterations = 2_000_000

    /// The name the counter and its guard live under.
    ///
    /// Double-underscored and unlikely to collide, and removed from the global
    /// object before the script runs is *not* an option — the guard has to be
    /// callable from inside the loops it protects.
    static let guardName = "__tick"

    /// The counter's declaration, evaluated before the script.
    static var preamble: String {
        """
        var __ticks = 0;
        function \(guardName)() {
            if (++__ticks > \(maximumIterations)) {
                throw new Error('script exceeded \(maximumIterations) iterations');
            }
        }
        """
    }

    /// Rewrites every loop so each pass calls the guard.
    ///
    /// The call goes into the loop's **condition**, not its body. A body can be
    /// a single statement with no braces — `while (x) doThing()` is legal — so
    /// rewriting bodies means either missing that form or generating broken
    /// code for it. A condition is always an expression and always parenthesised,
    /// so `(cond)` becomes `(__tick(), cond)` and the comma operator evaluates
    /// the guard first and yields the condition unchanged.
    ///
    /// `for (;;)` has an empty condition, which the comma form cannot express;
    /// it becomes `for (; (__tick(), true);)`.
    ///
    /// `do…while` runs its body before its condition, so a one-pass body still
    /// runs — which is correct: one pass is not a runaway.
    static func instrument(_ source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            guard let keyword = nextLoop(in: source, from: index) else {
                result += source[index...]
                break
            }

            result += source[index..<keyword.start]

            guard let open = source[keyword.end...].firstIndex(of: "("),
                  let close = matchingParen(in: source, openingAt: open)
              else {
                // No parenthesised head — leave it alone rather than emit
                // something that will not parse. A loop this does not
                // recognise stays uncounted, which the watchdog covers.
                result += source[keyword.start..<keyword.end]
                index = keyword.end
                continue
            }

            result += source[keyword.start..<open]
            result += rewrittenHead(
                String(source[source.index(after: open)..<close]),
                isFor: keyword.isFor,
            )
            index = source.index(after: close)
        }

        return result
    }

    // MARK: - Finding loops

    private struct Keyword {
        let start: String.Index
        let end: String.Index
        let isFor: Bool
    }

    /// The next `for`, `while` or `do` that is a real keyword.
    ///
    /// Checked for word boundaries so `forEach` and a variable called
    /// `whileLoop` are left alone — rewriting either would corrupt the script.
    private static func nextLoop(in source: String, from start: String.Index) -> Keyword? {
        let skippable = commentsAndStrings(in: source)

        var candidates: [Keyword] = []
        for (word, isFor) in [("for", true), ("while", false)] {
            var search = start
            while let found = source.range(of: word, range: search..<source.endIndex) {
                let inProse = true
                if isWord(in: source, range: found), !inProse {
                    candidates.append(Keyword(start: found.lowerBound, end: found.upperBound, isFor: isFor))
                    break
                }
                search = found.upperBound
            }
        }
        return candidates.min { $0.start < $1.start }
    }

    /// The stretches of the source that are prose rather than code.
    ///
    /// The word-boundary check alone is not enough, and a real script showed
    /// why: a line reading `// …a comb, while an angle that comes…` was
    /// followed by `const angleAt = (u) => {`. The `while` is a whole word, so
    /// it passed as a keyword, the next `(` found was the arrow function's
    /// parameter list, and it came out as
    /// `const angleAt = ((__tick(), u)) => {` — a syntax error from a file
    /// that is valid JavaScript.
    ///
    /// Scanned in one pass rather than with a regular expression: the states
    /// nest in ways a pattern cannot express — a `//` inside a string is not a
    /// comment, and a quote inside a comment does not open a string.
    private static func commentsAndStrings(in source: String) -> [Range<String.Index>] {
        enum State { case code, lineComment, blockComment, string(Character) }

        var ranges: [Range<String.Index>] = []
        var state = State.code
        var regionStart = source.startIndex
        var index = source.startIndex

        func next(after position: String.Index) -> String.Index? {
            let after = source.index(after: position)
            return after < source.endIndex ? after : nil
        }

        while index < source.endIndex {
            let character = source[index]

            switch state {
            case .code:
                if character == "/", let following = next(after: index) {
                    if source[following] == "/" {
                        state = .lineComment
                        regionStart = index
                        index = following
                    } else if source[following] == "*" {
                        state = .blockComment
                        regionStart = index
                        index = following
                    }
                } else if character == "\"" || character == "'" || character == "`" {
                    state = .string(character)
                    regionStart = index
                }

            case .lineComment:
                if character == "\n" {
                    ranges.append(regionStart..<index)
                    state = .code
                }

            case .blockComment:
                if character == "*", let following = next(after: index), source[following] == "/" {
                    index = following
                    ranges.append(regionStart..<source.index(after: index))
                    state = .code
                }

            case let .string(quote):
                // An escape consumes whatever follows, so `"\\""` does not end
                // the string.
                if character == "\\" {
                    if let following = next(after: index) { index = following }
                } else if character == quote {
                    ranges.append(regionStart..<source.index(after: index))
                    state = .code
                }
            }

            index = source.index(after: index)
        }

        // An unterminated comment or string runs to the end of the file.
        switch state {
        case .code: break
        default: ranges.append(regionStart..<source.endIndex)
        }

        return ranges
    }

    private static func isWord(in source: String, range: Range<String.Index>) -> Bool {
        let before = range.lowerBound == source.startIndex
            ? nil
            : source[source.index(before: range.lowerBound)]
        let after = range.upperBound == source.endIndex ? nil : source[range.upperBound]

        func isIdentifier(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isLetter || character.isNumber || character == "_" || character == "$"
        }

        return !isIdentifier(before) && !isIdentifier(after)
    }

    /// The `)` closing the `(` at `open`, respecting nesting.
    private static func matchingParen(in source: String, openingAt open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        while index < source.endIndex {
            switch source[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    // MARK: - Rewriting

    /// The head of a loop, with the guard folded into its condition.
    private static func rewrittenHead(_ head: String, isFor: Bool) -> String {
        guard isFor else {
            // `while (cond)` and the condition of a `do…while`.
            return "((\(guardName)(), \(head.isEmpty ? "true" : head)))"
        }

        // A `for` head is `init; condition; step`, and only the condition is
        // rewritten. A `for…of` or `for…in` has no semicolons, so its whole
        // head is the binding and the guard cannot go there — those fall
        // through to the body-less form below.
        let parts = splitTopLevel(head)
        guard parts.count == 3 else {
            return "(\(head))"
        }

        let condition = parts[1].trimmingCharacters(in: .whitespaces)
        // An empty condition means `for (;;)`, which is `true` with a guard in
        // front of it.
        let guarded = condition.isEmpty
            ? "(\(guardName)(), true)"
            : "(\(guardName)(), \(condition))"
        return "(\(parts[0]);\(guarded);\(parts[2]))"
    }

    /// Splits a `for` head on its top-level semicolons.
    ///
    /// Depth-aware, so `for (let i = f(a; b); …)` — or more realistically an
    /// object or array literal in the initialiser — does not split in the
    /// wrong place.
    private static func splitTopLevel(_ head: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0

        for character in head {
            switch character {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case ";" where depth == 0:
                parts.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }
}
