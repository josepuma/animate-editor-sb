@testable import StoryboardCore
import Foundation

/// Two commands of one family overlapping in time on one sprite.
///
/// osu! does not add them: the last written wins at every instant, so the
/// sprite tugs between two paths. Families are what share a property — `_M`
/// with its single-axis forms, `_S` with `_V`. Touching is not overlapping:
/// one move ending where the next starts is how a path is written.
///
/// And no sprite mixes `_M` with `_MX`/`_MY` even apart in time: the resolver,
/// like osu!, lets an axis command override `_M` outright and holds its start
/// before its first command, which is what hid the Rise/Fall entrance. The
/// same for `_S` with `_V`.
enum TextOverlapGuard {
    static func family(_ kind: CommandKind) -> String? {
        switch kind {
        case .move, .moveX, .moveY: "position"
        case .scale, .vectorScale: "scale"
        case .rotate: "rotation"
        case .fade: "opacity"
        case .color: "colour"
        case .parameter: nil
        }
    }

    static func violations(_ sprite: StoryboardSprite) -> [String] {
        var found: [String] = []
        let commands = sprite.commands
        for i in commands.indices {
            guard let a = family(commands[i].kind) else { continue }
            for j in commands.indices where j > i && family(commands[j].kind) == a {
                let x = commands[i], y = commands[j]
                if x.startTime < y.endTime, y.startTime < x.endTime {
                    found.append("\(sprite.id): \(a) \(x.kind)[\(x.startTime)…\(x.endTime)] × \(y.kind)[\(y.startTime)…\(y.endTime)]")
                }
            }
        }
        let kinds = Set(commands.map(\.kind))
        if kinds.contains(.move), kinds.contains(.moveX) || kinds.contains(.moveY) {
            found.append("\(sprite.id): mixes _M with a single-axis move")
        }
        // Nor `_S` with `_V`: osu! multiplies the two while the resolver lets
        // `V` override `S`, so a sprite holding both draws one way here and
        // another in the game — a Breathe on `_S` beside a stretched entrance
        // is exactly that.
        if kinds.contains(.scale), kinds.contains(.vectorScale) {
            found.append("\(sprite.id): mixes _S with _V")
        }
        return found
    }
}
