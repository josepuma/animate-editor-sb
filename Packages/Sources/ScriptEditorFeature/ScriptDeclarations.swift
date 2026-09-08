import Foundation

/// What the script itself declares: its variables, and its functions.
///
/// Completion knew the host's API and nothing about the code in front of it, so
/// `count` — declared on the line above — was not offered while `duration` was.
/// That is backwards: the names somebody just wrote are the ones they are most
/// likely to type next.
///
/// Found by scanning rather than parsing. A parser would know scope, and scope
/// is the thing this deliberately ignores: a `const` inside a loop body is
/// offered outside it too. Being wrong that way costs an extra entry in a list;
/// a parser costs a parser, and this list is read on every keystroke.
enum ScriptDeclarations {
    /// One name the script introduced.
    struct Declaration: Equatable {
        let name: String
        /// `const`, `let`, `var` or `function` — shown so hover can say what
        /// kind of thing it is, which is as much as a scan can honestly claim.
        let keyword: String
        /// The line it was written on, one-based, for hover to point at.
        let line: Int
    }

    /// Every name declared in `text`.
    ///
    /// Later declarations of the same name win, so re-declaring in a loop
    /// reports the most recent line rather than the first.
    static func all(in text: String) -> [Declaration] {
        var found: [String: Declaration] = [:]

        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            // Comments are skipped whole. A `// const fake = 1` offered as a
            // real name is worse than missing one: it says something exists
            // that does not.
            let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""

            for declaration in declarations(in: String(code), line: index + 1) {
                found[declaration.name] = declaration
            }
        }

        // By name, so the list is stable between keystrokes — a completion list
        // that reorders as you type is a list you cannot aim at.
        return found.values.sorted { $0.name < $1.name }
    }

    // MARK: - One line

    private static func declarations(in code: String, line: Int) -> [Declaration] {
        var results: [Declaration] = []

        for keyword in ["const", "let", "var", "function"] {
            var search = code.startIndex
            while let range = code.range(of: keyword, range: search..<code.endIndex) {
                search = range.upperBound

                // A word boundary on both sides, so `constant` is not a `const`
                // and a property called `.let` is not a declaration.
                guard isWordBoundary(before: range.lowerBound, in: code),
                      range.upperBound < code.endIndex,
                      code[range.upperBound].isWhitespace
                else { continue }

                if let name = name(after: range.upperBound, in: code) {
                    results.append(Declaration(name: name, keyword: keyword, line: line))
                }
            }
        }

        return results
    }

    private static func name(after start: String.Index, in code: String) -> String? {
        var index = start
        while index < code.endIndex, code[index].isWhitespace {
            index = code.index(after: index)
        }

        var name = ""
        while index < code.endIndex {
            let character = code[index]
            guard character.isLetter || character.isNumber || character == "_" || character == "$" else {
                break
            }
            name.append(character)
            index = code.index(after: index)
        }

        // A digit cannot start one, and destructuring (`const { a } = x`)
        // yields nothing here — a scan that guessed at those would offer names
        // that are not there.
        guard let first = name.first, first.isLetter || first == "_" || first == "$" else {
            return nil
        }
        return name
    }

    private static func isWordBoundary(before index: String.Index, in code: String) -> Bool {
        guard index > code.startIndex else { return true }
        let previous = code[code.index(before: index)]
        return !(previous.isLetter || previous.isNumber || previous == "_" || previous == "$" || previous == ".")
    }
}
