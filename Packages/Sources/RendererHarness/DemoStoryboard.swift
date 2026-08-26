import Foundation

/// Generates a `.osb` exercising the features the renderer needs to prove:
/// fades, moves, rotation, scaling, colour tinting, additive blending, flips
/// and loops — at a sprite count high enough to be a real workload.
enum DemoStoryboard {
    /// - Parameter ringCount: sprites per orbiting ring. Raise it to stress-test.
    static func make(ringCount: Int = 120) -> String {
        var lines = ["[Events]"]

        // ── Backdrop: a slow colour wash ──
        lines.append(#"Sprite,Background,Centre,"square.png",320,240"#)
        lines.append("_S,0,0,8000,9,9")
        lines.append("_F,0,0,8000,1,1")
        lines.append("_C,0,0,4000,20,24,48,60,20,80")
        lines.append("_C,0,4000,8000,60,20,80,20,24,48")

        // ── Orbiting ring: additive, rotating, pulsing ──
        for index in 0..<ringCount {
            let angle = Double(index) / Double(ringCount) * 2 * .pi
            let radius = 150.0
            let x = 320 + cos(angle) * radius
            let y = 240 + sin(angle) * radius
            let phase = Double(index) / Double(ringCount) * 2000

            lines.append(#"Sprite,Foreground,Centre,"circle.png",\#(fmt(x)),\#(fmt(y))"#)
            lines.append("_P,0,0,0,A")
            lines.append("_S,0,0,8000,0.35,0.35")
            lines.append("_F,0,0,500,0,1")
            lines.append("_F,0,7500,8000,1,0")

            // Hue sweep around the ring.
            let (r, g, b) = hue(Double(index) / Double(ringCount))
            lines.append("_C,0,0,8000,\(r),\(g),\(b),\(r),\(g),\(b)")

            // Breathing pulse, offset per sprite so the ring shimmers.
            lines.append("_L,\(Int(phase)),8")
            lines.append("__S,5,0,500,0.35,0.7")
            lines.append("__S,5,500,1000,0.7,0.35")
        }

        // ── Orbiting satellites: rotation plus vector scale ──
        for index in 0..<24 {
            let angle = Double(index) / 24 * 2 * .pi
            let x = 320 + cos(angle) * 300
            let y = 240 + sin(angle) * 190

            lines.append(#"Sprite,Foreground,Centre,"square.png",\#(fmt(x)),\#(fmt(y))"#)
            lines.append("_F,0,0,600,0,0.9")
            lines.append("_F,0,7400,8000,0.9,0")
            lines.append("_S,0,0,8000,0.5,0.5")
            lines.append("_R,0,0,8000,0,\(fmt(Double.pi * 4)))")
            lines.append("_C,0,0,8000,255,200,120,255,200,120")
            // Flip halfway, to prove mirroring works.
            if index.isMultiple(of: 2) {
                lines.append("_P,0,4000,8000,H")
            }
        }

        // ── Centrepiece: scales, rotates and crosses the canvas ──
        lines.append(#"Sprite,Overlay,Centre,"circle.png",320,240"#)
        lines.append("_F,0,0,800,0,1")
        lines.append("_F,0,7200,8000,1,0")
        lines.append("_S,17,0,2000,0.2,1.4")
        lines.append("_S,17,2000,4000,1.4,0.6")
        lines.append("_S,17,4000,8000,0.6,1.2")
        lines.append("_R,0,0,8000,0,\(fmt(Double.pi * 2)))")
        lines.append("_M,17,0,4000,320,240,520,180")
        lines.append("_M,17,4000,8000,520,180,120,320")
        lines.append("_C,0,0,8000,255,255,255,120,220,255")

        return lines.joined(separator: "\n")
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Simple hue sweep, returning 0–255 channels.
    private static func hue(_ position: Double) -> (Int, Int, Int) {
        let h = position * 6
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let q = Int((1 - f) * 255)
        let t = Int(f * 255)

        return switch sector {
        case 0: (255, t, 0)
        case 1: (q, 255, 0)
        case 2: (0, 255, t)
        case 3: (0, q, 255)
        case 4: (t, 0, 255)
        default: (255, 0, q)
        }
    }
}
