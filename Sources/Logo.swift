import AppKit
import SwiftUI

/// Hourglass whose sand drains with the phase's progress: top bulb empties, bottom bulb fills,
/// a thin stream falls while the timer runs. One drawing serves the pill, menu bar and app icon.
struct HourglassView: View {
    var progress: Double
    var color: Color
    var sand: Color? = nil      // defaults to `color`
    var flowing = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let p = min(max(progress, 0), 1)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            let line = max(1, w * 0.075)

            // Caps.
            for y in [0.06, 0.94] as [CGFloat] {
                let bar = Path(roundedRect: CGRect(x: 0.16 * w, y: y * h - line * 0.8, width: 0.68 * w, height: line * 1.6),
                               cornerRadius: line * 0.8)
                ctx.fill(bar, with: .color(color))
            }
            // Glass: two bulbs meeting at a narrow neck.
            var glass = Path()
            glass.move(to: pt(0.27, 0.12))
            glass.addCurve(to: pt(0.46, 0.48), control1: pt(0.25, 0.32), control2: pt(0.40, 0.42))
            glass.addCurve(to: pt(0.27, 0.88), control1: pt(0.40, 0.58), control2: pt(0.25, 0.68))
            glass.move(to: pt(0.73, 0.12))
            glass.addCurve(to: pt(0.54, 0.48), control1: pt(0.75, 0.32), control2: pt(0.60, 0.42))
            glass.addCurve(to: pt(0.73, 0.88), control1: pt(0.60, 0.58), control2: pt(0.75, 0.68))
            ctx.stroke(glass, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .round))

            let sandFill = GraphicsContext.Shading.color(sand ?? color)
            // Half-width of the glass interior at height y (approximates the bulb curve).
            func half(_ y: CGFloat) -> CGFloat {
                let d = abs(y - 0.5) / 0.36            // 0 at the neck, 1 at the caps
                return 0.035 + 0.17 * pow(min(d, 1), 0.75)
            }
            // Top bulb: sand rests on the neck, its surface sinking as time passes.
            let topLow: CGFloat = 0.46, topHigh: CGFloat = 0.20
            let topLevel = topLow - (topLow - topHigh) * CGFloat(1 - p)
            if p < 0.995 {
                var s = Path()
                s.move(to: pt(0.5 - half(topLevel), topLevel))
                s.addLine(to: pt(0.5 + half(topLevel), topLevel))
                stride(from: topLevel, through: topLow, by: 0.02).forEach { s.addLine(to: pt(0.5 + half($0), $0)) }
                stride(from: topLow, through: topLevel, by: -0.02).forEach { s.addLine(to: pt(0.5 - half($0), $0)) }
                s.closeSubpath()
                ctx.fill(s, with: sandFill)
            }
            // Bottom bulb: a mound that grows with progress.
            let botBase: CGFloat = 0.84, botTop: CGFloat = 0.58
            let botLevel = botBase - (botBase - botTop) * CGFloat(p)
            if p > 0.005 {
                var b = Path()
                b.move(to: pt(0.5 - half(botBase), botBase))
                stride(from: botBase, through: botLevel, by: -0.02).forEach { b.addLine(to: pt(0.5 - half($0), $0)) }
                b.addQuadCurve(to: pt(0.5 + half(botLevel), botLevel), control: pt(0.5, botLevel - 0.07))
                stride(from: botLevel, through: botBase, by: 0.02).forEach { b.addLine(to: pt(0.5 + half($0), $0)) }
                b.closeSubpath()
                ctx.fill(b, with: sandFill)
            }
            // Falling stream through the neck.
            if flowing && p > 0.005 && p < 0.995 {
                var stream = Path()
                stream.move(to: pt(0.5, 0.47))
                stream.addLine(to: pt(0.5, botLevel - 0.05))
                ctx.stroke(stream, with: sandFill, style: StrokeStyle(lineWidth: max(0.8, w * 0.045), lineCap: .round))
            }
        }
    }
}

enum Logo {
    @MainActor private static var cache: [Int: NSImage] = [:]

    /// Template image for the menu bar, quantised to 24 sand levels so it is rendered at most ~50 times.
    @MainActor static func menuBar(progress: Double, flowing: Bool) -> NSImage {
        let level = Int((min(max(progress, 0), 1) * 24).rounded())
        let key = level * 2 + (flowing ? 1 : 0)
        if let img = cache[key] { return img }
        let renderer = ImageRenderer(content:
            HourglassView(progress: Double(level) / 24, color: .black, flowing: flowing).frame(width: 14, height: 18))
        renderer.scale = 2
        let img = renderer.nsImage ?? NSImage()
        img.isTemplate = true
        cache[key] = img
        return img
    }
}
