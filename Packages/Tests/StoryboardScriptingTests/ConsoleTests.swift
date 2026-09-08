import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// What a script printed.
///
/// `console.log` was installed as a no-op so a script reaching for it would not
/// die — the right instinct, the wrong result: somebody logs precisely when
/// they cannot work out what a script did, and a log going nowhere is help
/// missing at the one moment it was wanted.
@Suite("Script console", .serialized)
struct ConsoleTests {
    private func run(_ source: String) -> ScriptRuntime.Outcome {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: 1,
        ))
    }

    @Test("a logged line is captured")
    func lineIsCaptured() {
        let outcome = run("console.log('hello'); sprite(Image.soft)")

        #expect(outcome.logs.map(\.message) == ["hello"])
        #expect(outcome.logs.first?.level == .log)
    }

    @Test("each level keeps its own", arguments: [
        ("console.log('a')", ScriptRuntime.LogLine.Level.log),
        ("console.warn('a')", .warn),
        ("console.error('a')", .error),
    ])
    func levelsAreKept(source: String, expected: ScriptRuntime.LogLine.Level) {
        #expect(run("\(source); sprite(Image.soft)").logs.first?.level == expected)
    }

    @Test("lines keep their order")
    func orderIsKept() {
        let outcome = run("""
        for (let i = 0; i < 3; i++) console.log('line ' + i)
        sprite(Image.soft)
        """)

        #expect(outcome.logs.map(\.message) == ["line 0", "line 1", "line 2"])
    }

    /// Logging an object is most of what logging is for.
    ///
    /// Through `toString` an object is `[object Object]`, which is the least
    /// useful thing it could say.
    @Test("an object is printed readably")
    func objectIsReadable() {
        let message = run("console.log({ x: 1, y: 2 }); sprite(Image.soft)").logs.first?.message

        #expect(message?.contains("\"x\":1") == true, "got \(message ?? "nothing")")
    }

    @Test("numbers and arrays print", arguments: [
        ("console.log(42)", "42"),
        ("console.log([1, 2])", "[1,2]"),
        ("console.log(true)", "true"),
        ("console.log(null)", "null"),
    ])
    func valuesPrint(source: String, expected: String) {
        #expect(run("\(source); sprite(Image.soft)").logs.first?.message == expected)
    }

    /// The logs travel with a failure, which is when they matter most.
    @Test("a thrown script keeps what it printed")
    func throwKeepsLogs() {
        let outcome = run("""
        console.log('got here')
        throw new Error('deliberate')
        """)

        #expect(!outcome.diagnostics.isEmpty)
        #expect(outcome.logs.map(\.message) == ["got here"])
    }

    /// A log inside a loop over two thousand particles is two thousand lines.
    @Test("output is capped, and says so")
    func cappedWithNotice() {
        let outcome = run("""
        for (let i = 0; i < 500; i++) console.log(i)
        sprite(Image.soft)
        """)

        #expect(outcome.logs.count == LogCollector.maximumLines + 1)
        #expect(outcome.logs.last?.message.contains("more line") == true)
        // The earliest are kept: the first lines of a loop are what tell you
        // the loop is wrong.
        #expect(outcome.logs.first?.message == "0")
    }

    /// A script that printed nothing reports nothing.
    @Test("silence stays silent")
    func silence() {
        #expect(run("sprite(Image.soft)").logs.isEmpty)
    }
}
