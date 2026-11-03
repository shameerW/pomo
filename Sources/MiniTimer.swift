import AppKit
import SwiftUI

/// Always-on-top desk ornament: a brass hourglass standing on a walnut plinth. The sand in the glass
/// *is* the timer; the brass plate on the plinth carries the time, music and pause controls.
/// Works regardless of whether the menu-bar item is visible (notch / Menu Bar settings can hide it).
struct MiniTimerView: View {
    @Environment(Engine.self) private var engine
    @State private var angle = 0.0          // hourglass rotation during a flip
    @State private var lift: CGFloat = 0    // it rises off the table while turning
    @State private var flipping = false
    @State private var hovering = false
    var onOpen: () -> Void

    /// Overall size of the ornament; every dimension below derives from it.
    /// Base dimensions at 100%; the user's size setting (drag grip or slider, 70–180%) scales everything.
    static func glass(_ s: CGFloat) -> CGSize { CGSize(width: 78 * s, height: 108 * s) }
    static func tableWidth(_ s: CGFloat) -> CGFloat { 172 * s }
    static let sizeRange: ClosedRange<Double> = 0.7...1.8
    /// The bonsai stands on the left of the tabletop, between the edge and the hourglass.
    static func plantInset(_ s: CGFloat) -> CGFloat { 2 * s }
    private var s: CGFloat { engine.settings.widgetScale }
    var onResize: () -> Void = {}
    @State private var dragStartScale: Double?

    var body: some View {
        VStack(spacing: -10 * s) {   // glass base overlaps the tabletop: it stands *on* it
            ZStack(alignment: .bottom) {
                RealHourglass(progress: flipping ? 1 : engine.progress, flowing: engine.isRunning && !flipping)
                    .frame(width: Self.glass(s).width, height: Self.glass(s).height)
                    .rotationEffect(.degrees(angle))
                    .offset(y: lift)
                    .contentShape(Rectangle())
                    .onTapGesture { tapGlass() }
                    .help(glassHelp)
                if engine.settings.plantOn {
                    DeskPlant(blocks: engine.plantBlocks, health: engine.plantHealth, scale: s)
                        .help(Plant.tooltip(blocks: engine.plantBlocks, health: engine.plantHealth))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Self.plantInset(s))
                        .offset(y: 4 * s)
                }
            }
            .frame(width: Self.tableWidth(s))
            .zIndex(1)
            Plinth(width: Self.tableWidth(s), glassWidth: Self.glass(s).width, scale: s) {
                HStack(spacing: 5 * s) {
                    BrassKnob(symbol: audioSymbol, dimmed: !engine.audioOn, size: 22 * s) { engine.toggleMusic() }
                        .help(audioHelp)
                    BrassPlate(text: engine.clock, scale: s)
                        .onTapGesture { onOpen() }
                        .help("Open Pomo")
                    BrassKnob(symbol: engine.isRunning ? "pause.fill" : "play.fill",
                              ring: engine.phase.tint, size: 22 * s) { engine.toggle() }
                        .help(engine.isRunning ? "Pause" : "Resume")
                    BrassKnob(symbol: "goforward.5", size: 22 * s) { engine.extend(minutes: 5) }
                        .help("+5 min more \(engine.extendTarget.title.lowercased()) (right-click: +3 / +10)")
                        .contextMenu {
                            ForEach([3, 5, 10], id: \.self) { m in
                                Button("+\(m) min more \(engine.extendTarget.title.lowercased())") { engine.extend(minutes: m) }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 3 * s) {
            if engine.settings.quoteOnWidget && engine.settings.quotesOn {
                QuoteSlip(quote: engine.quote, width: Self.tableWidth(s) - 10, scale: s)
                    .onTapGesture { onOpen() }
            }
        }
        .padding(8)
        .overlay(alignment: .topTrailing) {
            // Hide button: appears on hover (⌃⌥P does the same from anywhere).
            Button { engine.toggleWidget() } label: {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .help("Hide the hourglass (⌃⌥P)")
            .opacity(hovering ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
            // Resize grip: drag to scale the whole ornament (also in Settings). A native handle, because the
            // panel is "movable by background" and would otherwise start a window drag instead.
            ZStack {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.6))
                ResizeGrip(
                    began: { dragStartScale = engine.settings.widgetScale },
                    dragged: { dx, dy in
                        let start = dragStartScale ?? engine.settings.widgetScale
                        let delta = (dx + dy) / 2 / 172
                        engine.settings.widgetScale = min(max(start + delta, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
                    },
                    ended: { dragStartScale = nil })
            }
            .frame(width: 22, height: 22)
            .opacity(hovering || dragStartScale != nil ? 1 : 0)
            .help("Drag to resize")
        }
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { hovering = h } }
        .onChange(of: engine.settings.widgetScale) { _, _ in onResize() }
        .environment(\.decor, engine.settings.decor)
        .onChange(of: engine.phase) { _, _ in flip() }
    }

    private var audioSymbol: String {
        guard engine.audioOn else { return "speaker.slash.fill" }
        return engine.phase == .focus ? "music.note" : "megaphone.fill"
    }

    private var audioHelp: String {
        engine.phase == .focus
            ? (engine.settings.musicOn ? "Music off" : "Music on")
            : (engine.settings.breakTalksOn ? "Motivational talks off" : "Motivational talks on")
    }

    private var glassHelp: String {
        if engine.phase != .focus { return "Click: flip — end the break and start focusing" }
        return engine.isRunning ? "Click: open Pomo · Drag: move" : "Click: flip — start focusing"
    }

    /// Clicking the glass "turns it over": start an idle focus block, or cut a break short.
    private func tapGlass() {
        if engine.phase != .focus { engine.skip() }          // phase change triggers the flip
        else if !engine.isRunning { flip(); engine.start() }
        else { onOpen() }
    }

    /// Lift, turn 180° and set down. The finished state (bottom full) turned upside down looks exactly like
    /// a fresh phase (top full), so the sand is swapped back without animation once the turn completes.
    private func flip() {
        guard !flipping else { return }
        flipping = true
        withAnimation(.easeOut(duration: 0.25)) { lift = -10 * s }
        withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) { angle = 180 } completion: {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { angle = 0; flipping = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { lift = 0 }
        }
    }
}

// MARK: - Materials

enum FrameMaterial: String, CaseIterable, Codable {
    case brass, silver, oak, walnut, ebony, mahogany
    var label: String { rawValue.capitalized }
    var metal: Metal? { self == .brass ? .brass : self == .silver ? .silver : nil }
    var texture: String { rawValue }
}

enum TableMaterial: String, CaseIterable, Codable {
    case walnut, oak, ebony, mahogany, slate, marble
    var label: String { rawValue.capitalized }
    var texture: String { rawValue }
    var isLight: Bool { self == .oak || self == .marble }
}

enum SandColor: String, CaseIterable, Codable {
    case golden, white, rose, obsidian
    var label: String { rawValue.capitalized }
    var colors: (light: Color, mid: Color, dark: Color) {
        switch self {
        case .golden: (Color(red: 0.96, green: 0.88, blue: 0.70), Color(red: 0.89, green: 0.77, blue: 0.56), Color(red: 0.72, green: 0.58, blue: 0.38))
        case .white: (Color(white: 0.99), Color(red: 0.92, green: 0.91, blue: 0.88), Color(red: 0.74, green: 0.73, blue: 0.70))
        case .rose: (Color(red: 0.98, green: 0.84, blue: 0.82), Color(red: 0.91, green: 0.67, blue: 0.66), Color(red: 0.72, green: 0.47, blue: 0.47))
        case .obsidian: (Color(white: 0.42), Color(white: 0.22), Color(white: 0.08))
        }
    }
}

/// The ornament's look, chosen in Settings and passed down through the environment.
struct Decor: Equatable {
    var frame: FrameMaterial = .brass
    var table: TableMaterial = .walnut
    var sand: SandColor = .golden
    /// Plate and knobs match a silver frame; otherwise they stay brass.
    var fittings: Metal { frame == .silver ? .silver : .brass }
}

private struct DecorKey: EnvironmentKey { static let defaultValue = Decor() }
extension EnvironmentValues {
    var decor: Decor {
        get { self[DecorKey.self] }
        set { self[DecorKey.self] = newValue }
    }
}

struct Metal: Equatable {
    let shadow: Color, dark: Color, mid: Color, bright: Color, ink: Color
    static let brass = Metal(shadow: Color(red: 0.30, green: 0.20, blue: 0.07), dark: Color(red: 0.50, green: 0.36, blue: 0.13),
                             mid: Color(red: 0.80, green: 0.62, blue: 0.29), bright: Color(red: 0.99, green: 0.91, blue: 0.64),
                             ink: Color(red: 0.24, green: 0.15, blue: 0.05))
    static let silver = Metal(shadow: Color(red: 0.22, green: 0.24, blue: 0.27), dark: Color(red: 0.47, green: 0.49, blue: 0.53),
                              mid: Color(red: 0.74, green: 0.76, blue: 0.80), bright: Color(red: 0.98, green: 0.99, blue: 1.0),
                              ink: Color(red: 0.14, green: 0.15, blue: 0.17))

    /// Polished-cylinder look: dark edges, a sharp highlight left of centre, a softer reflection on the right.
    func cylinder(from x0: CGFloat, to x1: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: [
            .init(color: shadow, location: 0), .init(color: mid, location: 0.16), .init(color: bright, location: 0.30),
            .init(color: mid, location: 0.46), .init(color: dark, location: 0.70), .init(color: mid, location: 0.84),
            .init(color: shadow, location: 1)]),
            startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0))
    }
}

/// Procedural wood/stone textures (tools/make_textures.py), loaded once.
enum Texture {
    static let images: [String: NSImage] = {
        var out: [String: NSImage] = [:]
        let dir = ProcessInfo.processInfo.environment["POMO_TEXTURES"]
        for name in TableMaterial.allCases.map(\.texture) {
            if let url = Bundle.main.url(forResource: "Texture-\(name)", withExtension: "png"), let img = NSImage(contentsOf: url) { out[name] = img }
            else if let dir, let img = NSImage(contentsOfFile: "\(dir)/Texture-\(name).png") { out[name] = img }
        }
        return out
    }()

    /// Draw a texture into `path`, sampling `region` so different parts don't repeat the same grain.
    static func fill(_ ctx: inout GraphicsContext, _ path: Path, texture: String, region: CGRect, shade: Double = 0) {
        ctx.drawLayer { g in
            g.clip(to: path)
            if let img = images[texture] { g.draw(Image(nsImage: img).resizable(), in: region) }
            else { g.fill(path, with: .color(Color(red: 0.45, green: 0.28, blue: 0.14))) }
            if shade > 0 { g.fill(path, with: .color(.black.opacity(shade))) }
            if shade < 0 { g.fill(path, with: .color(.white.opacity(-shade))) }
        }
    }
}

/// Seeded grain positions so the sand texture is stable frame to frame.
private let sandGrains: [(x: Double, y: Double, r: Double, light: Bool)] = {
    var s: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    return (0..<520).map { _ in (rnd(), rnd(), 0.35 + rnd() * 0.45, rnd() > 0.55) }
}()


// MARK: - Hourglass

struct RealHourglass: View {
    var progress: Double
    var flowing: Bool

    var body: some View {
        ZStack {
            HourglassFrame(layer: .back)
            // Sand bodies change once a second; only the falling stream animates (15 fps, frozen while paused).
            SandLayer(progress: progress, flowing: flowing, time: 0, part: .bodies)
            TimelineView(.animation(minimumInterval: 1 / 15, paused: !flowing)) { ctx in
                SandLayer(progress: progress, flowing: flowing, time: ctx.date.timeIntervalSinceReferenceDate, part: .stream)
            }
            GlassFront()
            HourglassFrame(layer: .front)
        }
        .drawingGroup()
    }
}

/// Geometry shared by every layer of the hourglass.
private struct HG {
    let w: CGFloat, h: CGFloat
    var disc: CGFloat { h * 0.085 }                 // disc thickness
    var face: CGFloat { disc * 0.62 }               // visible top face (ellipse height)
    var glassRect: CGRect { CGRect(x: w * 0.17, y: disc * 0.75, width: w * 0.66, height: h - disc * 1.55) }
    var neckY: CGFloat { glassRect.midY }
    var glass: Path { HourglassShape().path(in: glassRect) }
    init(_ size: CGSize) { w = size.width; h = size.height }
}

struct HourglassFrame: View {
    enum Layer { case back, front }
    let layer: Layer
    @Environment(\.decor) private var decor

    var body: some View {
        Canvas { ctx, size in
            let g = HG(size)
            if layer == .back {
                // Rear pillar, seen through the glass: thinner and dimmer.
                spindle(&ctx, x: g.w / 2, top: g.disc * 0.6, bottom: g.h - g.disc * 0.6, r: g.w * 0.028, alpha: 0.55, g: g)
                return
            }
            spindle(&ctx, x: g.w * 0.075, top: g.disc * 0.6, bottom: g.h - g.disc * 0.6, r: g.w * 0.042, alpha: 1, g: g)
            spindle(&ctx, x: g.w * 0.925, top: g.disc * 0.6, bottom: g.h - g.disc * 0.6, r: g.w * 0.042, alpha: 1, g: g)
            disc(&ctx, y: 0, g: g, seed: 0.1)
            disc(&ctx, y: g.h - g.disc, g: g, seed: 0.6)
        }
    }

    /// A turned disc: metal (polished rim, brushed face) or wood (textured rim and face).
    private func disc(_ ctx: inout GraphicsContext, y: CGFloat, g: HG, seed: CGFloat) {
        let rim = Path(roundedRect: CGRect(x: 0, y: y + g.face / 2, width: g.w, height: g.disc - g.face / 2), cornerRadius: g.disc * 0.35)
        let face = Path(ellipseIn: CGRect(x: 0, y: y, width: g.w, height: g.face))
        if let metal = decor.frame.metal {
            ctx.fill(rim, with: metal.cylinder(from: 0, to: g.w))
            ctx.fill(rim, with: .linearGradient(Gradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)]),
                                                startPoint: CGPoint(x: 0, y: y + g.face / 2), endPoint: CGPoint(x: 0, y: y + g.disc)))
            ctx.fill(face, with: .linearGradient(Gradient(colors: [metal.bright, metal.mid, metal.dark]),
                                                 startPoint: CGPoint(x: g.w * 0.2, y: y), endPoint: CGPoint(x: g.w * 0.9, y: y + g.face)))
            ctx.drawLayer { l in
                l.clip(to: face)
                for k in 1...3 {
                    let inset = CGFloat(k) * g.w * 0.09
                    l.stroke(Path(ellipseIn: CGRect(x: inset, y: y + CGFloat(k) * g.face * 0.09, width: g.w - inset * 2, height: g.face * (1 - CGFloat(k) * 0.18))),
                             with: .color(.black.opacity(0.10)), lineWidth: 0.5)
                }
                l.addFilter(.blur(radius: 1.2))
                l.fill(Path(ellipseIn: CGRect(x: g.w * 0.18, y: y + g.face * 0.15, width: g.w * 0.30, height: g.face * 0.35)), with: .color(.white.opacity(0.55)))
            }
            ctx.stroke(face, with: .color(metal.shadow.opacity(0.8)), lineWidth: 0.6)
        } else {
            let tex = decor.frame.texture
            Texture.fill(&ctx, rim, texture: tex, region: CGRect(x: -g.w * seed * 4, y: y - 20, width: g.w * 5, height: 60), shade: 0.30)
            ctx.fill(rim, with: .linearGradient(Gradient(stops: [
                .init(color: .black.opacity(0.35), location: 0), .init(color: .white.opacity(0.12), location: 0.35),
                .init(color: .clear, location: 0.55), .init(color: .black.opacity(0.45), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: g.w, y: 0)))
            Texture.fill(&ctx, face, texture: tex, region: CGRect(x: -g.w * seed * 3, y: y - 30, width: g.w * 4, height: 70), shade: 0.04)
            ctx.fill(face, with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.20)]),
                                                 startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: g.w, y: y + g.face)))
            ctx.stroke(face, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        }
        var groove = Path()
        groove.move(to: CGPoint(x: 1.5, y: y + g.disc * 0.78)); groove.addLine(to: CGPoint(x: g.w - 1.5, y: y + g.disc * 0.78))
        ctx.stroke(groove, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
    }

    /// A turned pillar: beads at the ends and the middle; metal or wood shading.
    private func spindle(_ ctx: inout GraphicsContext, x: CGFloat, top: CGFloat, bottom: CGFloat, r: CGFloat, alpha: Double, g: HG) {
        let len = bottom - top
        func radius(_ t: CGFloat) -> CGFloat {
            let bead = { (c: CGFloat, w: CGFloat) -> CGFloat in exp(-pow((t - c) / w, 2)) }
            return r * (0.78 + 0.55 * bead(0.06, 0.05) + 0.55 * bead(0.94, 0.05) + 0.45 * bead(0.5, 0.06) + 0.15 * bead(0.28, 0.1) + 0.15 * bead(0.72, 0.1))
        }
        var p = Path()
        let steps = 40
        p.move(to: CGPoint(x: x - radius(0), y: top))
        for i in 0...steps { let t = CGFloat(i) / CGFloat(steps); p.addLine(to: CGPoint(x: x - radius(t), y: top + len * t)) }
        for i in stride(from: steps, through: 0, by: -1) { let t = CGFloat(i) / CGFloat(steps); p.addLine(to: CGPoint(x: x + radius(t), y: top + len * t)) }
        p.closeSubpath()
        ctx.opacity = alpha
        if let metal = decor.frame.metal {
            ctx.fill(p, with: metal.cylinder(from: x - r * 1.4, to: x + r * 1.4))
        } else {
            Texture.fill(&ctx, p, texture: decor.frame.texture, region: CGRect(x: x - 40, y: top - 10, width: 80, height: len + 20), shade: 0.12)
            ctx.fill(p, with: .linearGradient(Gradient(stops: [
                .init(color: .black.opacity(0.55), location: 0), .init(color: .white.opacity(0.22), location: 0.38),
                .init(color: .clear, location: 0.6), .init(color: .black.opacity(0.6), location: 1)]),
                startPoint: CGPoint(x: x - r * 1.4, y: 0), endPoint: CGPoint(x: x + r * 1.4, y: 0)))
        }
        ctx.opacity = 1
    }
}

struct SandLayer: View {
    enum Part { case bodies, stream }
    var progress: Double
    var flowing: Bool
    var time: Double
    var part: Part
    @Environment(\.decor) private var decor

    var body: some View {
        Canvas { ctx, size in
            let g = HG(size)
            let (sandLight, sandMid, sandDark) = decor.sand.colors
            let p = min(max(progress, 0), 1)
            let gr = g.glassRect
            let w = g.w, neck = g.neckY
            ctx.clip(to: g.glass)

            // Top bulb: level sinks; a funnel crater deepens over the neck while it drains.
            let topFull = gr.minY + (neck - gr.minY) * 0.16
            let level = topFull + (neck - topFull) * CGFloat(pow(p, 0.85))
            var top = Path()
            if part == .bodies && p < 0.995 {
                // One smooth funnel bowl: the surface sags towards the neck as sand drains through it.
                let crater = flowing ? min(9, (neck - level) * 0.45) : 1.5
                top.move(to: CGPoint(x: gr.minX - 2, y: level))
                top.addCurve(to: CGPoint(x: gr.maxX + 2, y: level),
                             control1: CGPoint(x: w / 2 - gr.width * 0.18, y: level + crater * 1.35),
                             control2: CGPoint(x: w / 2 + gr.width * 0.18, y: level + crater * 1.35))
                top.addLine(to: CGPoint(x: gr.maxX + 2, y: neck + 1))
                top.addLine(to: CGPoint(x: gr.minX - 2, y: neck + 1))
                top.closeSubpath()
                ctx.fill(top, with: .linearGradient(Gradient(colors: [sandLight, sandMid, sandDark]),
                                                    startPoint: CGPoint(x: gr.minX, y: level), endPoint: CGPoint(x: gr.maxX, y: neck)))
                // Surface sheen.
                var sheen = Path(); sheen.move(to: CGPoint(x: gr.minX + 2, y: level + 0.8)); sheen.addQuadCurve(to: CGPoint(x: w / 2 - 6, y: level + crater), control: CGPoint(x: w / 2 - gr.width * 0.2, y: level + crater * 0.9))
                ctx.stroke(sheen, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
            }

            // Bottom bulb: a cone at the angle of repose, lit from the left.
            let floor = gr.maxY - 1
            let pileH = (floor - neck) * 0.86 * CGFloat(pow(p, 0.8))
            var cone = Path()
            if part == .bodies && p > 0.005 {
                let apex = CGPoint(x: w / 2, y: floor - pileH)
                let spread = gr.width * (0.55 + 0.45 * CGFloat(p))
                cone.move(to: CGPoint(x: gr.minX - 2, y: floor + 2))
                cone.addLine(to: CGPoint(x: gr.minX - 2, y: max(apex.y + pileH * 0.55, floor - 3)))
                cone.addLine(to: CGPoint(x: w / 2 - spread / 2, y: floor - pileH * 0.18))
                cone.addQuadCurve(to: apex, control: CGPoint(x: w / 2 - 4, y: apex.y - 1))
                cone.addQuadCurve(to: CGPoint(x: w / 2 + spread / 2, y: floor - pileH * 0.18), control: CGPoint(x: w / 2 + 4, y: apex.y - 1))
                cone.addLine(to: CGPoint(x: gr.maxX + 2, y: max(apex.y + pileH * 0.55, floor - 3)))
                cone.addLine(to: CGPoint(x: gr.maxX + 2, y: floor + 2))
                cone.closeSubpath()
                ctx.fill(cone, with: .linearGradient(Gradient(colors: [sandLight, sandMid, sandDark]),
                                                     startPoint: CGPoint(x: w / 2 - spread / 2, y: 0), endPoint: CGPoint(x: w / 2 + spread / 2, y: 0)))
            }

            // Grain texture inside both sand bodies.
            for region in [top, cone] where !region.isEmpty {
                ctx.drawLayer { l in
                    l.clip(to: region)
                    for grain in sandGrains {
                        let pt = CGPoint(x: gr.minX + grain.x * gr.width, y: gr.minY + grain.y * gr.height)
                        l.fill(Path(ellipseIn: CGRect(x: pt.x, y: pt.y, width: grain.r, height: grain.r)),
                               with: .color(grain.light ? .white.opacity(0.45) : sandDark.opacity(0.8)))
                    }
                }
            }

            // Stream and falling grains through the neck, with a puff where it lands.
            if part == .stream && flowing && p > 0.002 && p < 0.998 {
                let landing = floor - pileH
                var stream = Path(); stream.move(to: CGPoint(x: w / 2, y: neck - 2)); stream.addLine(to: CGPoint(x: w / 2, y: landing))
                ctx.stroke(stream, with: .color(sandMid.opacity(0.9)), lineWidth: 0.9)
                for i in 0..<9 {
                    let ph = (time * 1.4 + Double(i) / 9).truncatingRemainder(dividingBy: 1)
                    let y = neck + (landing - neck) * CGFloat(ph * ph)
                    let x = w / 2 + CGFloat(sin(Double(i) * 12.9898 + time) * 0.9)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(sandLight))
                }
                for i in 0..<4 {
                    let ph = (time * 2.3 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                    let dx = CGFloat((i % 2 == 0 ? -1 : 1) * (2 + 4 * ph)), dy = CGFloat(-3 * ph * (1 - ph) * 4)
                    ctx.fill(Path(ellipseIn: CGRect(x: w / 2 + dx - 0.6, y: landing + dy - 0.6, width: 1.2, height: 1.2)),
                             with: .color(sandLight.opacity(1 - ph)))
                }
            }
        }
    }
}

/// The glass itself: thick-looking edges, a bright specular streak, faint reflections.
struct GlassFront: View {
    var body: some View {
        Canvas { ctx, size in
            let g = HG(size)
            let glass = g.glass
            let gr = g.glassRect
            ctx.fill(glass, with: .linearGradient(Gradient(colors: [.white.opacity(0.10), .white.opacity(0.02), .white.opacity(0.08)]),
                                                  startPoint: CGPoint(x: gr.minX, y: 0), endPoint: CGPoint(x: gr.maxX, y: 0)))
            // Edge darkening: glass looks thicker where you see through it at an angle.
            ctx.drawLayer { l in
                l.clip(to: glass)
                l.addFilter(.blur(radius: 2.2))
                l.stroke(glass, with: .color(.black.opacity(0.28)), lineWidth: 4)
            }
            ctx.stroke(glass, with: .color(.white.opacity(0.75)), lineWidth: 0.9)
            // Specular streaks.
            func streak(_ pts: [CGPoint], width: CGFloat, alpha: Double) {
                var s = Path(); s.move(to: pts[0]); s.addQuadCurve(to: pts[2], control: pts[1])
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 0.5))
                    l.stroke(s, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            streak([CGPoint(x: gr.minX + gr.width * 0.20, y: gr.minY + 6), CGPoint(x: gr.minX + gr.width * 0.08, y: gr.minY + gr.height * 0.22),
                    CGPoint(x: gr.minX + gr.width * 0.33, y: g.neckY - gr.height * 0.09)], width: 2.4, alpha: 0.85)
            streak([CGPoint(x: gr.minX + gr.width * 0.33, y: g.neckY + gr.height * 0.10), CGPoint(x: gr.minX + gr.width * 0.08, y: gr.maxY - gr.height * 0.22),
                    CGPoint(x: gr.minX + gr.width * 0.20, y: gr.maxY - 7)], width: 1.8, alpha: 0.6)
            streak([CGPoint(x: gr.maxX - gr.width * 0.16, y: gr.minY + 9), CGPoint(x: gr.maxX - gr.width * 0.07, y: gr.minY + gr.height * 0.2),
                    CGPoint(x: gr.maxX - gr.width * 0.2, y: gr.minY + gr.height * 0.33)], width: 1.1, alpha: 0.4)
        }
    }
}

/// Classic hourglass silhouette: two rounded bulbs meeting at a narrow neck.
struct HourglassShape: Shape {
    func path(in r: CGRect) -> Path {
        let midX = r.midX, midY = r.midY
        let neck = r.width * 0.06
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.10, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.10, y: r.minY))
        p.addCurve(to: CGPoint(x: midX + neck, y: midY),
                   control1: CGPoint(x: r.maxX + r.width * 0.06, y: r.minY + r.height * 0.28),
                   control2: CGPoint(x: midX + neck, y: midY - r.height * 0.12))
        p.addCurve(to: CGPoint(x: r.maxX - r.width * 0.10, y: r.maxY),
                   control1: CGPoint(x: midX + neck, y: midY + r.height * 0.12),
                   control2: CGPoint(x: r.maxX + r.width * 0.06, y: r.maxY - r.height * 0.28))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.10, y: r.maxY))
        p.addCurve(to: CGPoint(x: midX - neck, y: midY),
                   control1: CGPoint(x: r.minX - r.width * 0.06, y: r.maxY - r.height * 0.28),
                   control2: CGPoint(x: midX - neck, y: midY + r.height * 0.12))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.10, y: r.minY),
                   control1: CGPoint(x: midX - neck, y: midY - r.height * 0.12),
                   control2: CGPoint(x: r.minX - r.width * 0.06, y: r.minY + r.height * 0.28))
        p.closeSubpath()
        return p
    }
}

// MARK: - Plinth

/// Plinth (wood or stone): polished top in perspective (with a faint reflection of the hourglass base),
/// bevelled front face carrying the brass controls.
struct Plinth<Content: View>: View {
    let width: CGFloat
    let glassWidth: CGFloat
    var scale: CGFloat = 1
    @ViewBuilder var content: Content
    private var topH: CGFloat { 18 * scale }
    private var frontH: CGFloat { 38 * scale }
    @Environment(\.decor) private var decor

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                let w = size.width
                let inset: CGFloat = 10
                var top = Path()
                top.move(to: CGPoint(x: inset, y: 0)); top.addLine(to: CGPoint(x: w - inset, y: 0))
                top.addLine(to: CGPoint(x: w, y: topH)); top.addLine(to: CGPoint(x: 0, y: topH)); top.closeSubpath()
                Texture.fill(&ctx, top, texture: decor.table.texture, region: CGRect(x: -40, y: -60, width: w + 260, height: 150), shade: -0.04)
                // Perspective light: far edge darker, near edge lighter; varnish gloss band.
                ctx.fill(top, with: .linearGradient(Gradient(colors: [.black.opacity(0.30), .clear, .white.opacity(0.08)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: topH)))
                ctx.fill(top, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.15), .init(color: .white.opacity(0.16), location: 0.45), .init(color: .clear, location: 0.75)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: w, y: topH)))
                // Contact shadow + soft reflection of the hourglass foot on the varnish.
                let cx = w / 2
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 3))
                    l.fill(Path(ellipseIn: CGRect(x: cx - glassWidth * 0.62, y: topH * 0.18, width: glassWidth * 1.24, height: topH * 0.7)),
                           with: .color(.black.opacity(0.55)))
                }
                ctx.drawLayer { l in
                    l.clip(to: top)
                    l.addFilter(.blur(radius: 1.2))
                    l.fill(Path(roundedRect: CGRect(x: cx - glassWidth / 2, y: topH * 0.55, width: glassWidth, height: topH * 0.45), cornerRadius: 3),
                           with: .linearGradient(Gradient(colors: [Color(red: 0.4, green: 0.25, blue: 0.12).opacity(0.5), .clear]),
                                                 startPoint: CGPoint(x: 0, y: topH * 0.55), endPoint: CGPoint(x: 0, y: topH)))
                }
                // Front face.
                let front = Path(roundedRect: CGRect(x: 0, y: topH, width: w, height: frontH), cornerRadii: .init(bottomLeading: 5, bottomTrailing: 5))
                Texture.fill(&ctx, front, texture: decor.table.texture, region: CGRect(x: -120, y: topH - 90, width: w + 300, height: 190),
                             shade: decor.table.isLight ? 0.14 : 0.30)
                ctx.fill(front, with: .linearGradient(Gradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.35)]),
                                                      startPoint: CGPoint(x: 0, y: topH), endPoint: CGPoint(x: 0, y: topH + frontH)))
                // Bevel: bright arris on the top edge, thin dark line under it.
                var arris = Path(); arris.move(to: CGPoint(x: 0.5, y: topH + 0.6)); arris.addLine(to: CGPoint(x: w - 0.5, y: topH + 0.6))
                ctx.stroke(arris, with: .color(Color(red: 1, green: 0.86, blue: 0.62).opacity(0.75)), lineWidth: 1.1)
                var under = Path(); under.move(to: CGPoint(x: 0.5, y: topH + 2)); under.addLine(to: CGPoint(x: w - 0.5, y: topH + 2))
                ctx.stroke(under, with: .color(.black.opacity(0.35)), lineWidth: 0.7)
                // Side edges catch a little light.
                ctx.stroke(Path(CGRect(x: 0.5, y: topH, width: 0.1, height: frontH - 4)), with: .color(.white.opacity(0.12)), lineWidth: 1)
            }
            .frame(width: width, height: topH + frontH)
            .shadow(color: .black.opacity(0.5), radius: 7, y: 5)

            content
                .frame(height: frontH)
        }
    }
}

/// Engraved brass name plate showing the time.
struct BrassPlate: View {
    let text: String
    var scale: CGFloat = 1
    @Environment(\.decor) private var decor

    var body: some View {
        Text(text)
            .font(.system(size: 16 * scale, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(decor.fittings.ink)
            .shadow(color: .white.opacity(0.55), radius: 0, y: 0.8)          // engraved: light catches the lower lip
            .contentTransition(.numericText(countsDown: true))
            .frame(width: 66 * scale, height: 24 * scale)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [decor.fittings.bright, decor.fittings.mid, decor.fittings.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .white.opacity(0.35), location: 0.42), .init(color: .clear, location: 0.6)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(decor.fittings.shadow, lineWidth: 0.8))
                    .overlay(alignment: .leading) { screw.padding(.leading, 3) }
                    .overlay(alignment: .trailing) { screw.padding(.trailing, 3) }
                    .shadow(color: .black.opacity(0.5), radius: 1.2, y: 1)
            }
    }

    private var screw: some View {
        Circle()
            .fill(RadialGradient(colors: [decor.fittings.bright, decor.fittings.dark], center: .topLeading, startRadius: 0, endRadius: 3))
            .frame(width: 3.2, height: 3.2)
            .overlay(Rectangle().fill(.black.opacity(0.45)).frame(width: 2.4, height: 0.5).rotationEffect(.degrees(35)))
    }
}

/// Round brass knob with an engraved glyph; optional coloured ring shows the phase.
struct BrassKnob: View {
    let symbol: String
    var ring: Color? = nil
    var dimmed = false
    var size: CGFloat = 24
    let action: () -> Void
    @Environment(\.decor) private var decor

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(RadialGradient(colors: [decor.fittings.bright, decor.fittings.mid, decor.fittings.dark],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.62))
                Circle().strokeBorder(ring ?? decor.fittings.shadow, lineWidth: ring == nil ? 0.8 : 1.6)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .heavy))
                    .foregroundStyle(decor.fittings.ink.opacity(dimmed ? 0.45 : 1))
                    .shadow(color: .white.opacity(0.5), radius: 0, y: 0.7)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.55), radius: 1.5, y: 1.2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Resize grip

/// AppKit drag handle: claims the mouse (so the panel doesn't move) and reports the drag distance in points,
/// positive = right / down.
struct ResizeGrip: NSViewRepresentable {
    var began: () -> Void
    var dragged: (CGFloat, CGFloat) -> Void
    var ended: () -> Void

    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ v: GripView, context: Context) {
        v.began = began; v.dragged = dragged; v.ended = ended
    }

    final class GripView: NSView {
        var began: () -> Void = {}
        var dragged: (CGFloat, CGFloat) -> Void = { _, _ in }
        var ended: () -> Void = {}
        private var start: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() {
            if #available(macOS 15.0, *) {
                addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }
        override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; began() }
        override func mouseDragged(with event: NSEvent) {
            guard let s = start else { return }
            let now = NSEvent.mouseLocation                    // screen coordinates: y grows upwards
            dragged(now.x - s.x, s.y - now.y)
        }
        override func mouseUp(with event: NSEvent) { start = nil; ended() }
    }
}

// MARK: - Quote slip

/// A parchment note tucked in front of the plinth. Fixed height (4 lines) so the panel never resizes.
struct QuoteSlip: View {
    let quote: Quote
    let width: CGFloat
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("“\(quote.text)”")
                .font(.system(size: 11 * scale, design: .serif).italic())
                .lineLimit(4)
                .minimumScaleFactor(0.7)
            // Just the name on the slip ("Seneca, Letters to Lucilius" → "Seneca"); the window shows the full source.
            Text("— \(quote.author.components(separatedBy: ",").first ?? quote.author)")
                .font(.system(size: 9 * scale, design: .serif))
                .lineLimit(1)
                .opacity(0.75)
        }
        .foregroundStyle(Color(red: 0.25, green: 0.17, blue: 0.08))
        .padding(.horizontal, 8 * scale).padding(.vertical, 5 * scale)
        .frame(width: width, height: 76 * scale, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Color(red: 0.99, green: 0.96, blue: 0.87), Color(red: 0.93, green: 0.87, blue: 0.73)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(red: 0.62, green: 0.50, blue: 0.32).opacity(0.35), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
        }
        .rotationEffect(.degrees(-1.2))
        .id(quote)
        .transition(.opacity.combined(with: .offset(y: 3)))
        .animation(.easeInOut(duration: 0.6), value: quote)
    }
}

// MARK: - Panel

final class MiniTimerPanel: NSPanel {
    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        setContentSize(host.fittingSize)
        setFrameAutosaveName("PomoHourglass")
        if !setFrameUsingName("PomoHourglass"), let screen = NSScreen.main?.visibleFrame {
            // Default: top-right corner, just under the menu bar.
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 16, y: screen.maxY - frame.height - 10))
        }
    }

    override var canBecomeKey: Bool { false }

    /// Resize the panel to its content (after a size change), keeping the top-left corner fixed.
    func fitContent() {
        guard let size = contentView?.fittingSize, size != frame.size else { return }
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        clampToScreen()
    }

    /// Keep the whole widget visible, e.g. after it grows or the display arrangement changes.
    func clampToScreen() {
        guard let vis = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var o = frame.origin
        o.x = min(max(o.x, vis.minX + 4), vis.maxX - frame.width - 4)
        o.y = min(max(o.y, vis.minY + 4), vis.maxY - frame.height - 4)
        if o != frame.origin { setFrameOrigin(o) }
    }
}
