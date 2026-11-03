import SwiftUI

/// The desk bonsai: grows with every completed focus block, droops and yellows when breaks get skipped.
/// Pure function of (blocks, health): it only redraws when one of them changes.
enum PlantStage: Int, CaseIterable {
    case sprout, sapling, young, bonsai, flowering

    var name: String {
        switch self {
        case .sprout: "Sprout"
        case .sapling: "Sapling"
        case .young: "Young tree"
        case .bonsai: "Bonsai"
        case .flowering: "Flowering bonsai"
        }
    }

    /// Lifetime focus blocks needed to reach this stage.
    var threshold: Int { [0, 3, 10, 25, 60][rawValue] }

    static func of(_ blocks: Int) -> PlantStage { allCases.last { blocks >= $0.threshold } ?? .sprout }
}

enum Plant {
    /// 0…1 growth, continuous inside each stage so every block adds a little.
    static func growth(_ blocks: Int) -> Double {
        let knots: [(Int, Double)] = [(0, 0), (3, 0.12), (10, 0.36), (25, 0.66), (60, 0.94), (120, 1)]
        let b = max(0, blocks)
        for (a, z) in zip(knots, knots.dropFirst()) where b < z.0 {
            return a.1 + (z.1 - a.1) * Double(b - a.0) / Double(z.0 - a.0)
        }
        return 1
    }

    static func tooltip(blocks: Int, health: Double) -> String {
        let stage = PlantStage.of(blocks)
        var parts = [stage.name]
        if let next = PlantStage(rawValue: stage.rawValue + 1) {
            let n = next.threshold - blocks
            parts.append("\(n) block\(n == 1 ? "" : "s") to \(next == .flowering ? "flowering" : next.name.lowercased())")
        } else {
            parts.append("\(blocks) blocks")
        }
        parts.append("health \(Int((health * 100).rounded()))%")
        let hint = health < 0.6 ? "\nTake your breaks to bring it back." : ""
        return parts.joined(separator: " · ") + hint
    }
}

/// Deterministic random numbers so the same tree grows every time.
private struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

struct DeskPlant: View {
    let blocks: Int
    let health: Double
    var scale: CGFloat = 1

    static func size(_ s: CGFloat) -> CGSize { CGSize(width: 46 * s, height: 84 * s) }

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .frame(width: Self.size(scale).width, height: Self.size(scale).height)
            .accessibilityLabel(Plant.tooltip(blocks: blocks, health: health))
    }

    // MARK: drawing

    private func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let t = min(max(t, 0), 1)
        return Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let s = scale
        let g = Plant.growth(blocks)
        let h = min(max(health, 0), 1)
        let sick = min(1, max(0, (0.85 - h) / 0.7))   // 0 healthy … 1 very unwell
        let base = size.height - 6 * s                 // where the pot stands on the tabletop
        let cx = size.width / 2

        // Pot: glazed rectangular bonsai pot with little feet.
        let potW = (g < 0.12 ? 22 : 30) * s, potH = (g < 0.12 ? 11 : 10) * s
        let potTop = base - potH
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2.2 * s))
            l.fill(Path(ellipseIn: CGRect(x: cx - potW * 0.62, y: base - 2 * s, width: potW * 1.24, height: 5 * s)), with: .color(.black.opacity(0.5)))
        }
        for fx in [-1.0, 1.0] {
            ctx.fill(Path(roundedRect: CGRect(x: cx + fx * potW * 0.36 - 2 * s, y: base - 1.6 * s, width: 4 * s, height: 2.2 * s), cornerRadius: 0.8 * s),
                     with: .color(Color(red: 0.12, green: 0.15, blue: 0.17)))
        }
        var pot = Path()
        pot.move(to: CGPoint(x: cx - potW / 2, y: potTop))
        pot.addLine(to: CGPoint(x: cx + potW / 2, y: potTop))
        pot.addLine(to: CGPoint(x: cx + potW / 2 - 2.5 * s, y: base - 1.2 * s))
        pot.addLine(to: CGPoint(x: cx - potW / 2 + 2.5 * s, y: base - 1.2 * s))
        pot.closeSubpath()
        ctx.fill(pot, with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.50, blue: 0.55), Color(red: 0.20, green: 0.31, blue: 0.36), Color(red: 0.11, green: 0.17, blue: 0.21)]),
                                            startPoint: CGPoint(x: cx - potW / 2, y: potTop), endPoint: CGPoint(x: cx + potW / 2, y: base)))
        ctx.fill(pot, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.1), .init(color: .white.opacity(0.28), location: 0.3), .init(color: .clear, location: 0.45)]),
                                            startPoint: CGPoint(x: cx - potW / 2, y: potTop), endPoint: CGPoint(x: cx + potW / 2, y: potTop)))
        // Rim and soil with a little moss.
        let rim = CGRect(x: cx - potW / 2 - 1 * s, y: potTop - 1.6 * s, width: potW + 2 * s, height: 2.6 * s)
        ctx.fill(Path(roundedRect: rim, cornerRadius: 1 * s), with: .linearGradient(Gradient(colors: [Color(red: 0.48, green: 0.62, blue: 0.66), Color(red: 0.22, green: 0.33, blue: 0.38)]),
                                                                                        startPoint: CGPoint(x: 0, y: rim.minY), endPoint: CGPoint(x: 0, y: rim.maxY)))
        let soil = CGRect(x: cx - potW / 2 + 1 * s, y: potTop - 2.2 * s, width: potW - 2 * s, height: 1.8 * s)
        ctx.fill(Path(ellipseIn: soil), with: .color(Color(red: 0.22, green: 0.15, blue: 0.10)))
        if g >= 0.12 {
            ctx.fill(Path(ellipseIn: soil.insetBy(dx: potW * 0.18, dy: 0.2 * s).offsetBy(dx: -potW * 0.08, dy: -0.4 * s)),
                     with: .color(mix((0.30, 0.45, 0.20), (0.50, 0.45, 0.25), sick).opacity(0.9)))
        }
        let ground = potTop - 1.6 * s

        let leafA = (0.20, 0.47, 0.18), leafB = (0.42, 0.66, 0.26)          // healthy dark / light
        let sickA = (0.55, 0.45, 0.16), sickB = (0.83, 0.72, 0.30)          // yellowing
        let dark = mix(leafA, sickA, sick), light = mix(leafB, sickB, sick)

        var rng = Seeded(state: 7)

        // Fallen leaves on the table when it's unwell.
        if h < 0.75 {
            let n = min(7, Int((0.75 - h) * 10) + 1)
            var fr = Seeded(state: 99)
            for i in 0..<n {
                let side: Double = i.isMultiple(of: 2) ? -1 : 1
                let x = cx + side * (potW / 2 + fr.range(1, 8) * s)
                let y = base + fr.range(-1.5, 3) * s
                var leaf = Path(ellipseIn: CGRect(x: -2.2 * s, y: -1 * s, width: 4.4 * s, height: 2 * s))
                leaf = leaf.applying(CGAffineTransform(rotationAngle: fr.range(-0.8, 0.8))).applying(CGAffineTransform(translationX: x, y: y))
                ctx.fill(leaf, with: .color(mix((0.70, 0.55, 0.20), (0.55, 0.33, 0.14), fr.next())))
            }
        }

        // Sprout: a stem with two seed leaves that unfold over the first blocks.
        if g < 0.12 {
            let t = g / 0.12
            let stemH = (5 + 13 * t) * s
            let top = CGPoint(x: cx + sick * 3 * s, y: ground - stemH + sick * 3 * s)
            var stem = Path()
            stem.move(to: CGPoint(x: cx, y: ground))
            stem.addQuadCurve(to: top, control: CGPoint(x: cx - 2 * s, y: ground - stemH * 0.6))
            ctx.stroke(stem, with: .color(mix((0.35, 0.55, 0.22), (0.62, 0.55, 0.25), sick)), style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
            let leafLen = (4 + 4 * t) * s
            for side in [-1.0, 1.0] {
                let droop = 0.35 + sick * 0.9
                var leaf = Path(ellipseIn: CGRect(x: 0, y: -leafLen * 0.22, width: leafLen, height: leafLen * 0.44))
                leaf = leaf.applying(CGAffineTransform(rotationAngle: side > 0 ? -0.35 + droop : .pi + 0.35 - droop))
                    .applying(CGAffineTransform(translationX: top.x, y: top.y))
                ctx.fill(leaf, with: .linearGradient(Gradient(colors: [light, dark]), startPoint: CGPoint(x: top.x, y: top.y - leafLen), endPoint: CGPoint(x: top.x, y: top.y + leafLen)))
            }
            return
        }

        // Tree: an informal-upright trunk (gentle S-curve) with branches revealed as it grows.
        let t = (g - 0.12) / 0.88                                   // 0…1 from sapling to full bonsai
        let height = (18 + 46 * t) * s
        let thick = (1.6 + 5.2 * t) * s
        let p0 = CGPoint(x: cx, y: ground)
        let p3 = CGPoint(x: cx + 2 * s, y: ground - height)
        let c1 = CGPoint(x: cx - 7 * s * t - 2 * s, y: ground - height * 0.35)
        let c2 = CGPoint(x: cx + 8 * s * t + 2 * s, y: ground - height * 0.7)
        func trunk(_ u: CGFloat) -> CGPoint {
            let a = (1 - u) * (1 - u) * (1 - u), b = 3 * (1 - u) * (1 - u) * u, c = 3 * (1 - u) * u * u, d = u * u * u
            return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x, y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
        }
        let bark = Color(red: 0.36, green: 0.25, blue: 0.17), barkLight = Color(red: 0.55, green: 0.42, blue: 0.30)
        // Tapered trunk drawn as stacked segments.
        let steps = 24
        for i in 0..<steps {
            let u0 = CGFloat(i) / CGFloat(steps), u1 = CGFloat(i + 1) / CGFloat(steps)
            var seg = Path(); seg.move(to: trunk(u0)); seg.addLine(to: trunk(u1))
            let w = thick * (1 - 0.72 * u0) + 0.6 * s
            ctx.stroke(seg, with: .color(bark), style: StrokeStyle(lineWidth: w, lineCap: .round))
            ctx.stroke(seg.offsetBy(dx: -w * 0.18, dy: 0), with: .color(barkLight.opacity(0.55)), style: StrokeStyle(lineWidth: w * 0.3, lineCap: .round))
        }
        // Surface roots (nebari) once it's a proper bonsai.
        if t > 0.5 {
            for side in [-1.0, 1.0] {
                var root = Path(); root.move(to: CGPoint(x: cx, y: ground - 1 * s))
                root.addQuadCurve(to: CGPoint(x: cx + side * thick * 1.4, y: ground + 0.4 * s), control: CGPoint(x: cx + side * thick * 0.5, y: ground - 0.2 * s))
                ctx.stroke(root, with: .color(bark), style: StrokeStyle(lineWidth: thick * 0.45, lineCap: .round))
            }
        }

        // Branches: (position on trunk, side, length, rise, growth at which it appears).
        let specs: [(u: CGFloat, side: CGFloat, len: CGFloat, rise: CGFloat, born: Double)] = [
            (0.55, 1, 0.40, 0.10, 0.00), (0.70, -1, 0.36, 0.14, 0.08), (0.40, -1, 0.42, 0.04, 0.30),
            (0.84, 1, 0.26, 0.20, 0.42), (0.30, 1, 0.34, 0.02, 0.58), (0.62, -1, 0.22, 0.30, 0.72),
        ]
        var pads: [(CGPoint, CGFloat)] = [(CGPoint(x: p3.x, y: p3.y + 1 * s), (5 + 7 * t) * s)]   // apex
        let droop = CGFloat(sick) * 4 * s
        for b in specs where t >= b.born {
            let grow = CGFloat(min(1, (t - b.born) / 0.18))
            let start = trunk(b.u)
            let len = b.len * 0.74 * height * grow
            let end = CGPoint(x: start.x + b.side * len, y: start.y - b.rise * height * grow + droop * grow)
            var br = Path(); br.move(to: start)
            br.addQuadCurve(to: end, control: CGPoint(x: start.x + b.side * len * 0.5, y: start.y + 1.5 * s))
            ctx.stroke(br, with: .color(bark), style: StrokeStyle(lineWidth: max(0.8 * s, thick * 0.38 * (1 - b.u * 0.5)), lineCap: .round))
            pads.append((end, (3 + 5.5 * t) * s * (0.5 + 0.5 * grow)))
        }

        // Foliage pads: clouds of small leaves; leaf count follows growth so each block adds a few.
        let leavesPerPad = Int(16 + 40 * t)
        let thin = sick * 0.45                                      // sick trees lose some leaves
        for (center, r) in pads {
            let c = CGPoint(x: center.x, y: center.y + droop * 0.6)
            // Shaded underside first for depth.
            let blob = CGRect(x: c.x - r * 0.92, y: c.y - r * 0.42, width: r * 1.84, height: r * 0.88)
            ctx.fill(Path(ellipseIn: blob.offsetBy(dx: 0, dy: r * 0.12)), with: .color(.black.opacity(0.22)))
            ctx.fill(Path(ellipseIn: blob), with: .radialGradient(Gradient(colors: [light.opacity(0.95), dark, dark.opacity(0.85)]),
                                                                center: CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.1))
            for _ in 0..<leavesPerPad {
                let a = rng.range(0, 2 * .pi), d = sqrt(rng.next())
                let keep = rng.next()
                let lx = c.x + CGFloat(cos(a) * d) * r
                let ly = c.y - r * 0.15 + CGFloat(sin(a) * d) * r * 0.5
                let shade = rng.next()
                guard keep > thin else { continue }
                let lw = (2.2 + rng.range(0, 1.2)) * s
                var leaf = Path(ellipseIn: CGRect(x: -lw / 2, y: -lw * 0.22, width: lw, height: lw * 0.44))
                leaf = leaf.applying(CGAffineTransform(rotationAngle: rng.range(-0.6, 0.6) + Double(sick) * 0.9))
                    .applying(CGAffineTransform(translationX: lx, y: ly))
                ctx.fill(leaf, with: .color(shade > 0.55 - Double(ly < c.y ? 0.25 : 0) ? light : dark))
            }
        }

        // Blossoms once it flowers: more with every block past 60.
        if blocks >= PlantStage.flowering.threshold, h > 0.35 {
            let n = min(24, 6 + (blocks - PlantStage.flowering.threshold) / 2)
            var fr = Seeded(state: 31)
            for i in 0..<n {
                let (c, r) = pads[i % pads.count]
                let a = fr.range(0, 2 * .pi), d = sqrt(fr.next())
                let p = CGPoint(x: c.x + CGFloat(cos(a) * d) * r * 0.9, y: c.y - r * 0.25 + CGFloat(sin(a) * d) * r * 0.42 + droop * 0.6)
                let fr2 = 1.5 * s
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - fr2, y: p.y - fr2, width: fr2 * 2, height: fr2 * 2)),
                         with: .color(Color(red: 0.98, green: 0.74, blue: 0.82)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 0.5 * s, y: p.y - 0.5 * s, width: s, height: s)), with: .color(Color(red: 0.95, green: 0.85, blue: 0.4)))
            }
        }
    }
}
