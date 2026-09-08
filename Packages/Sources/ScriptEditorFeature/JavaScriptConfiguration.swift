import LanguageSupport
import RegexBuilder

/// How to colour a storyboard script.
///
/// Written here because `CodeEditorView` ships configurations for Swift,
/// Haskell, Agda, SQL and Cypher — not JavaScript. It is a tokenizer built from
/// regexes rather than a grammar, which is the known cost of this dependency:
/// genuinely awkward input will occasionally colour wrong. A regex literal
/// holding an apostrophe (`/it's/`) reads as an unterminated string; a template
/// literal with nested interpolation is matched as one span rather than as code
/// inside text.
///
/// Both are cosmetic faults in an editor that works, which is the trade that
/// was taken deliberately — the grammar-accurate alternative does not compile
/// on this toolchain at all.
public extension LanguageConfiguration {
    /// JavaScript, as a storyboard script uses it.
    static func javaScript(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        LanguageConfiguration(
            name: "JavaScript",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            // Single quotes, double quotes and backticks, each allowing an
            // escaped copy of its own delimiter. Backticks are in the same
            // alternation rather than handled separately: a template literal is
            // a string as far as colouring goes, and treating its `${…}` as
            // code would need a grammar.
            stringRegex: /"(?:\\"|[^"])*+"|'(?:\\'|[^'])*+'|`(?:\\`|[^`])*+`/,
            // No character literal in JavaScript. Left nil rather than pointed
            // at single quotes, which are already strings above.
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: "//",
            // Not actually nestable in JavaScript — `/* /* */` ends at the
            // first close — but the field names the delimiters and this is the
            // only place to give them.
            nestedComment: (open: "/*", close: "*/"),
            identifierRegex: identifierRegex,
            operatorRegex: operatorRegex,
            reservedIdentifiers: reservedIdentifiers,
            reservedOperators: [],
            languageService: languageService,
        )
    }

    /// Decimal, hex, binary, octal, exponent, and the numeric separator.
    private static var numberRegex: Regex<Substring> {
        Regex {
            ChoiceOf {
                // 0x1F, 0b1010, 0o777 — each with optional separators.
                Regex {
                    "0"
                    One(.anyOf("xX"))
                    OneOrMore(CharacterClass(.hexDigit, .anyOf("_")))
                }
                Regex {
                    "0"
                    One(.anyOf("bB"))
                    OneOrMore(CharacterClass(.anyOf("01_")))
                }
                Regex {
                    "0"
                    One(.anyOf("oO"))
                    OneOrMore(CharacterClass(.anyOf("01234567_")))
                }
                // 1, 1.5, .5, 1e3, 1.5e-3 — and the BigInt suffix.
                Regex {
                    ChoiceOf {
                        Regex {
                            OneOrMore(CharacterClass(.digit, .anyOf("_")))
                            Optionally {
                                "."
                                ZeroOrMore(CharacterClass(.digit, .anyOf("_")))
                            }
                        }
                        Regex {
                            "."
                            OneOrMore(CharacterClass(.digit, .anyOf("_")))
                        }
                    }
                    Optionally {
                        One(.anyOf("eE"))
                        Optionally(One(.anyOf("+-")))
                        OneOrMore(.digit)
                    }
                    Optionally("n")
                }
            }
        }
    }

    /// An identifier, including the `$` and `_` JavaScript allows.
    private static var identifierRegex: Regex<Substring> {
        Regex {
            CharacterClass(.word.subtracting(.digit), .anyOf("$"))
            ZeroOrMore(CharacterClass(.word, .anyOf("$")))
        }
    }

    private static var operatorRegex: Regex<Substring> {
        Regex {
            OneOrMore(.anyOf("+-*/%=<>!&|^~?:."))
        }
    }

    /// The reserved words, plus the globals a script is given.
    ///
    /// The storyboard API is in here on purpose: `sprite`, `duration` and
    /// `Image` are not JavaScript keywords, but in this editor they are exactly
    /// as fixed as `for` is — an author cannot redefine them, and colouring
    /// them is what tells someone the name they typed is the one the host
    /// provides rather than a typo.
    private static var reservedIdentifiers: [String] {
        keywords
    }

    /// The words the language itself reserves, plus what the host installs.
    private static var keywords: [String] {
        [
            // The language.
            "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "enum", "export",
            "extends", "false", "finally", "for", "function", "if", "implements",
            "import", "in", "instanceof", "interface", "let", "new", "null",
            "package", "private", "protected", "public", "return", "static",
            "super", "switch", "this", "throw", "true", "try", "typeof", "var",
            "void", "while", "with", "yield",
            // What the language gives you.
            "Array", "Boolean", "JSON", "Math", "Number", "Object", "String",
            "Symbol", "Map", "Set", "NaN", "Infinity", "undefined", "globalThis",
            "parseInt", "parseFloat", "isNaN", "isFinite",
            // What the host gives you.
            //
            // Duplicated from `ScriptEngine.allowedGlobals` rather than shared,
            // because this target does not depend on the scripting one and
            // should not: colouring is not running. The duplication is real
            // and the risk is real — a name coloured here that a script cannot
            // call says the call is fine right up until it throws — so a test
            // asserts every name in this group, which is what makes removing
            // one from the engine show up as a failing case here rather than as
            // a lie on screen.
            "sprite", "rng", "duration", "param", "params", "Image", "Ease",
            "Layer", "Origin", "console",
        ]
        // The members of those namespaces, so `Ease.quadOut` colours as one
        // thing rather than a coloured receiver and a plain word after it.
        //
        // Reported as "the enums have no syntax", and it was not a limitation
        // of regex highlighting — `Ease` was in the list and `quadOut` was
        // not. Tree-sitter would have coloured them by grammar; a table
        // colours them by being complete.
        //
        // Taken from `ScriptAPI` rather than written again, so the names that
        // colour are exactly the names that complete: a third copy of this
        // list is a third thing to keep in step, and the second copy was
        // already wrong once — all thirty-five easings were spelled backwards.
        + ScriptAPI.easings.map(\.name)
        + ScriptAPI.images.map(\.name)
        + ScriptAPI.layers.map(\.name)
        + ScriptAPI.origins.map(\.name)
        + ScriptAPI.spriteMethods.map(\.name)
        + ScriptAPI.randomMethods.map(\.name)
    }
}
