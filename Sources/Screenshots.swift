import AppKit
import SwiftUI

/// `Pomo --screenshots <dir>` renders README images from the real views with demo data, then quits.
/// It never touches the running app's state: Engine skips resume/persistence in this mode.
enum Screenshots {
    static let isActive = CommandLine.arguments.contains("--screenshots")

    @MainActor static func run() {
        let args = CommandLine.arguments
        let dir = args.firstIndex(of: "--screenshots").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "screenshots"
        try? FileManager.default.createDirectory(atPath: dir + "/frames", withIntermediateDirectories: true)

        let engine = Engine.shared
        engine.demo(phase: .focus, progress: 0.42, running: true, intention: "Draft the system design doc", today: 5)
        Music.shared.demo(Track(id: "demo", title: "Raag Yaman · bansuri", minutes: 43),
                          raga: Raga(name: "Yaman", time: "evening", mood: "serene, devotional"))

        // Style sheet: a few material combinations side by side.
        let combos: [(FrameMaterial, TableMaterial, SandColor, String)] = [
            (.brass, .walnut, .golden, "Brass · Walnut"), (.silver, .slate, .white, "Silver · Slate"),
            (.oak, .mahogany, .golden, "Oak · Mahogany"), (.ebony, .marble, .obsidian, "Ebony · Marble"),
        ]
        let sheet = HStack(spacing: 6) {
            ForEach(combos, id: \.3) { f, t, sand, label in
                VStack(spacing: 2) {
                    Shot(phase: .focus, progress: 0.45, clock: "13:46", showQuote: false)
                        .environment(\.decor, Decor(frame: f, table: t, sand: sand))
                    Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        save(sheet, to: "\(dir)/styles.png", scale: 2, background: true)

        // Main window.
        engine.demo(phase: .focus, progress: 0.42, running: true, intention: "Draft the system design doc", today: 5)
        let window = PopoverView().environment(engine)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(1)
        for (name, scheme) in [("window-dark", ColorScheme.dark), ("window-light", .light)] {
            save(window.environment(\.colorScheme, scheme), to: "\(dir)/\(name).png", scale: 2)
        }

        // Hero: the ornament and the window on a desktop-like backdrop.
        engine.demo(phase: .focus, progress: 0.42, running: true, intention: "Draft the system design doc", today: 5)
        let hero = HStack(alignment: .center, spacing: 90) {
            Shot(phase: .focus, progress: 0.42, clock: "14:30", showQuote: false, plant: (34, 0.95))
                .scaleEffect(1.55)
                .frame(width: 300, height: 380)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
            PopoverView().environment(engine)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
        }
        .padding(.horizontal, 140).padding(.vertical, 36)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.13, green: 0.10, blue: 0.22), Color(red: 0.32, green: 0.16, blue: 0.20), Color(red: 0.72, green: 0.38, blue: 0.24)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.40).opacity(0.45), .clear], center: UnitPoint(x: 0.22, y: 0.75), startRadius: 10, endRadius: 520)
                RadialGradient(colors: [Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.35), .clear], center: UnitPoint(x: 0.85, y: 0.1), startRadius: 10, endRadius: 480)
            }
        }
        save(hero, to: "\(dir)/hero.png", scale: 2)

        // Animated demo: a block draining (sped up), the flip, and the break starting.
        var i = 0
        func frame(_ v: some View) { save(v, to: String(format: "\(dir)/frames/f%03d.png", i), scale: 2, background: true); i += 1 }
        for k in 0..<48 {
            let p = Double(k) / 47
            frame(Shot(phase: .focus, progress: p, clock: clock(.focus, p), time: Double(k) / 15))
        }
        for k in 0..<14 {
            let t = Double(k) / 13
            let eased = 1 - pow(1 - t, 3)
            frame(Shot(phase: .shortBreak, progress: 1, clock: "5:00", angle: 180 * eased, lift: -9 * sin(.pi * t), flowing: false))
        }
        for k in 0..<22 {
            let p = Double(k) / 21 * 0.35
            frame(Shot(phase: .shortBreak, progress: p, clock: clock(.shortBreak, p), time: Double(k) / 15))
        }
        print("rendered \(i) frames + stills into \(dir)")
        exit(0)
    }

    private static func clock(_ phase: Phase, _ p: Double) -> String {
        let total = phase == .focus ? 1500.0 : (phase == .shortBreak ? 300 : 900)
        let s = Int((total * (1 - p)).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    @MainActor private static func save(_ view: some View, to path: String, scale: CGFloat, background: Bool = false) {
        let content = background
            ? AnyView(view.padding(18).background(LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.19), Color(red: 0.05, green: 0.06, blue: 0.10)],
                                                                 startPoint: .top, endPoint: .bottom)))
            : AnyView(view)
        let r = ImageRenderer(content: content)
        r.scale = scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// Static composition of the floating ornament for rendering (mirrors MiniTimerView's layout).
private struct Shot: View {
    var phase: Phase
    var progress: Double
    var clock: String
    var time: Double = 0
    var angle: Double = 0
    var lift: CGFloat = 0
    var flowing = true
    var showQuote = true
    var plant: (blocks: Int, health: Double)? = (34, 0.9)

    var body: some View {
        let s: CGFloat = 1
        VStack(spacing: -10 * s) {
            ZStack(alignment: .bottom) {
                ZStack {
                    HourglassFrame(layer: .back)
                    SandLayer(progress: progress, flowing: flowing, time: time, part: .bodies)
                    SandLayer(progress: progress, flowing: flowing, time: time, part: .stream)
                    GlassFront()
                    HourglassFrame(layer: .front)
                }
                .frame(width: MiniTimerView.glass(s).width, height: MiniTimerView.glass(s).height)
                .rotationEffect(.degrees(angle))
                .offset(y: lift)
                if let p = plant {
                    DeskPlant(blocks: p.blocks, health: p.health, scale: s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, MiniTimerView.plantInset(s))
                        .offset(y: 4 * s)
                }
            }
            .frame(width: MiniTimerView.tableWidth(s))
            .zIndex(1)
            Plinth(width: MiniTimerView.tableWidth(s), glassWidth: MiniTimerView.glass(s).width, scale: s) {
                HStack(spacing: 5 * s) {
                    BrassKnob(symbol: phase == .focus ? "music.note" : "megaphone.fill", size: 22 * s) {}
                    BrassPlate(text: clock, scale: s)
                    BrassKnob(symbol: "pause.fill", ring: phase.tint, size: 22 * s) {}
                    BrassKnob(symbol: "goforward.5", size: 22 * s) {}
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 3 * s) {
            if showQuote { QuoteSlip(quote: phase == .focus
                      ? Quote(text: "How we spend our days is, of course, how we spend our lives.", author: "Annie Dillard, The Writing Life")
                      : Quote(text: "Almost everything will work again if you unplug it for a few minutes, including you.", author: "Anne Lamott"),
                      width: MiniTimerView.tableWidth(s) - 10) }
        }
        .padding(8)
    }
}
