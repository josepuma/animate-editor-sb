import Foundation
import Testing
@testable import StoryboardCore

/// Command times reach the file as whole milliseconds.
///
/// osu! rejects a storyboard whose times carry a decimal point — not by drawing
/// it oddly, by refusing the file. And fractional times are the normal case
/// rather than an edge one: an effect divides its clip into segments, a beat at
/// 169.4 BPM is 354.19ms, and a script may put a command anywhere it likes.
@Suite("OSB command times")
struct OsbTimeTests {
    private func sprite(_ commands: [Command]) -> StoryboardSprite {
        var s = StoryboardSprite(id: "s", layer: .background, origin: .centre,
                                 filePath: "a.png", defaultX: 320, defaultY: 240)
        s.commands = commands
        return s
    }

    private func lines(_ sprite: StoryboardSprite) -> [String] {
        OsbWriter.write([sprite]).split(separator: "\n").map(String.init)
    }

    @Test("a fractional time is written whole")
    func fractional() {
        let out = lines(sprite([
            Command(easing: .linear, startTime: 354.19, endTime: 708.38,
                    payload: .fade(start: 0, end: 1)),
        ]))
        let command = out.first { $0.contains("F,") } ?? ""
        print("\n  \(command)")
        #expect(command.contains(",354,708,"), "times were not rounded: \(command)")
        #expect(!command.contains("."), "a decimal point reached the file: \(command)")
    }

    /// Rounded, not truncated.
    ///
    /// Truncation biases every command half a millisecond early, and upstream
    /// of a thousand of them that is drift rather than noise.
    @Test("times round to the nearer millisecond")
    func rounds() {
        let out = lines(sprite([
            Command(easing: .linear, startTime: 10.6, endTime: 20.4,
                    payload: .fade(start: 0, end: 1)),
        ]))
        let command = out.first { $0.contains("F,") } ?? ""
        print("  \(command)")
        #expect(command.contains(",11,20,"), "not rounded to nearest: \(command)")
    }

    /// Values keep their decimals — only TIMES are whole.
    ///
    /// The format is happy with a fractional position, and rounding one would
    /// quantise every sprite in the file to the pixel.
    @Test("positions keep their precision")
    func valuesKeepDecimals() {
        let out = lines(sprite([
            Command(easing: .linear, startTime: 0, endTime: 100,
                    payload: .move(startX: 12.25, startY: 8.5, endX: 300.75, endY: 240)),
        ]))
        let command = out.first { $0.contains("M,") } ?? ""
        print("  \(command)")
        #expect(command.contains("12.25"), "a position was rounded away: \(command)")
        #expect(command.contains("300.75"), "a position was rounded away: \(command)")
    }

    /// Two distinct times that round to the same millisecond.
    ///
    /// The writer spells "hold" as a blank end time, and it decides that by
    /// comparing the two BEFORE rounding — so a one-frame command whose ends
    /// round together would be written as `10,10` rather than as a hold. Both
    /// are legal and mean the same thing, so what matters is only that no
    /// decimal escapes.
    @Test("ends that round together stay whole")
    func collapsing() {
        let out = lines(sprite([
            Command(easing: .linear, startTime: 10.1, endTime: 10.4,
                    payload: .fade(start: 0, end: 1)),
        ]))
        let command = out.first { $0.contains("F,") } ?? ""
        print("  \(command)")
        #expect(!command.contains("."), "a decimal point reached the file: \(command)")
    }

    /// A loop's own start time is a time too.
    @Test("a loop start is written whole")
    func loopStart() {
        var s = sprite([])
        s.loops = [LoopGroup(startTime: 1234.56, loopCount: 3, commands: [
            Command(easing: .linear, startTime: 0, endTime: 500.5,
                    payload: .fade(start: 0, end: 1)),
        ])]
        let out = lines(s)
        let loop = out.first { $0.contains("L,") } ?? ""
        let body = out.first { $0.contains("F,") } ?? ""
        print("  \(loop)\n  \(body)")
        #expect(loop.contains("L,1235,3"), "the loop start was not rounded: \(loop)")
        #expect(!body.contains("."), "a decimal reached a loop body: \(body)")
    }

    /// Nothing in the file may carry a decimal in a time position.
    ///
    /// A sweep rather than a case: the writer emits nine payload kinds and a
    /// guard on one of them says nothing about the other eight.
    @Test("no command of any kind writes a fractional time")
    func everyKind() {
        let payloads: [Command.Payload] = [
            .fade(start: 0, end: 1),
            .move(startX: 0, startY: 0, endX: 1, endY: 1),
            .moveX(start: 0, end: 1),
            .moveY(start: 0, end: 1),
            .scale(start: 0, end: 1),
            .vectorScale(startX: 0, startY: 0, endX: 1, endY: 1),
            .rotate(start: 0, end: 1),
            .color(startR: 1, startG: 2, startB: 3, endR: 4, endG: 5, endB: 6),
            .parameter(.additive),
        ]

        for payload in payloads {
            let out = lines(sprite([
                Command(easing: .linear, startTime: 100.4, endTime: 900.7, payload: payload),
            ]))
            let command = out.first { $0.hasPrefix(" ") } ?? ""
            // The time fields are the third and fourth comma-separated parts.
            let parts = command.split(separator: ",", omittingEmptySubsequences: false)
            #expect(parts.count > 3, "unreadable line: \(command)")
            #expect(!parts[2].contains("."), "fractional start for \(payload): \(command)")
            #expect(!parts[3].contains("."), "fractional end for \(payload): \(command)")
        }
    }
}
