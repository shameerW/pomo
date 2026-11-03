import SwiftUI

extension Phase {
    var tint: Color {
        switch self {
        case .focus: Color(red: 0.96, green: 0.38, blue: 0.31)       // tomato
        case .shortBreak: Color(red: 0.20, green: 0.72, blue: 0.62)  // sea green
        case .longBreak: Color(red: 0.36, green: 0.52, blue: 0.95)   // calm blue
        }
    }
}

struct PopoverView: View {
    @Environment(Engine.self) private var engine
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            header
            ring
            intentionRow
            controls
            ExtendRow()
            if engine.settings.quotesOn { QuoteCard(quote: engine.quote, tint: engine.phase.tint) }
            MusicRow()
            Divider()
            stats
            if showSettings { SettingsPanel() }
        }
        .padding(18)
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
    }

    private var header: some View {
        HStack {
            Label(engine.phase.title, systemImage: engine.phase.symbol)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(engine.phase.tint)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(engine.phase.tint.opacity(0.14), in: Capsule())
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<engine.settings.longEvery, id: \.self) { i in
                    Circle()
                        .fill(i < engine.completedInCycle ? engine.phase.tint : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .help("Pomodoros in this cycle")
            Button { engine.toggleWidget() } label: {
                Image(systemName: engine.settings.miniTimerOn ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .help(engine.settings.miniTimerOn ? "Hide the floating hourglass (⌃⌥P)" : "Show the floating hourglass (⌃⌥P)")
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(
                    AngularGradient(colors: [engine.phase.tint.opacity(0.55), engine.phase.tint], center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .drawingGroup()  // conic gradient on the GPU; on the CPU it costs ~40% while animating
            VStack(spacing: 2) {
                Text(engine.clock)
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
    }

    private var statusLine: String {
        if engine.isRunning { return engine.phase == .focus ? "stay with it" : "breathe" }
        if engine.pausedRemaining != nil { return "paused" }
        return "ready"
    }

    @ViewBuilder private var intentionRow: some View {
        @Bindable var engine = engine
        if engine.phase == .focus {
            if engine.isIdle {
                TextField("What will you focus on?", text: $engine.intention)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { engine.start() }
            } else if !engine.intention.isEmpty {
                Label(engine.intention, systemImage: "scope")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            CircleButton(symbol: "arrow.counterclockwise", help: "Reset cycle") { engine.reset() }
            Button { engine.toggle() } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .foregroundStyle(.white)
                    .background(engine.phase.tint, in: Circle())
                    .shadow(color: engine.phase.tint.opacity(0.4), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(engine.isRunning ? "Pause (space)" : "Start (space)")
            CircleButton(symbol: "forward.end.fill", help: "Skip to next phase") { engine.skip() }
        }
    }

    private var stats: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text("\(engine.today.count) block\(engine.today.count == 1 ? "" : "s")  ·  \(formatMinutes(engine.todayMinutes))")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("7-day avg").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f / day", engine.sevenDayAverage))
                    .font(.system(.callout, design: .rounded))
            }
            Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .help("Settings")
        }
    }

    private func formatMinutes(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
}

struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct QuoteCard: View {
    let quote: Quote
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("“\(quote.text)”")
                .font(.system(.callout, design: .serif))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(quote.author)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 10)
        }
        .id(quote)
        .transition(.opacity)
    }
}

struct SettingsPanel: View {
    @Environment(Engine.self) private var engine
    @State private var launchAtLogin = Engine.shared.launchAtLogin
    @State private var apiKey = Secrets.youtubeAPIKey

    var body: some View {
        @Bindable var engine = engine
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Focus  \(engine.settings.focusMin) min", value: $engine.settings.focusMin, in: 5...120, step: 5)
            Stepper("Short break  \(engine.settings.shortMin) min", value: $engine.settings.shortMin, in: 1...30)
            Stepper("Long break  \(engine.settings.longMin) min", value: $engine.settings.longMin, in: 5...60, step: 5)
            Stepper("Long break every  \(engine.settings.longEvery)", value: $engine.settings.longEvery, in: 2...8)
            Toggle("Auto-start breaks", isOn: $engine.settings.autoStartBreaks)
            Toggle("Auto-start focus", isOn: $engine.settings.autoStartFocus)
            Toggle("Show quotes", isOn: $engine.settings.quotesOn)
            Toggle("Motivational talks during breaks", isOn: $engine.settings.breakTalksOn)
            Toggle("Show the video player", isOn: $engine.settings.showPlayer)
                .help("YouTube's terms expect the video to be visible while it plays. Hiding it is your call.")
            HStack {
                Text("YouTube API key")
                SecureField("optional", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, v in Secrets.youtubeAPIKey = v }
            }
            .help("With a key, search uses the official YouTube Data API instead of the public results page.")
            Toggle("Floating hourglass (⌃⌥P)", isOn: $engine.settings.miniTimerOn)
            Toggle("Quote under the hourglass", isOn: $engine.settings.quoteOnWidget)
            Toggle("Desk bonsai (grows with focus, wilts if you skip breaks)", isOn: $engine.settings.plantOn)
            HStack {
                Text("Hourglass size")
                Slider(value: $engine.settings.widgetScale, in: MiniTimerView.sizeRange)
                Text("\(Int(engine.settings.widgetScale * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
            Picker("Hourglass", selection: $engine.settings.frameMaterial) {
                ForEach(FrameMaterial.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Table", selection: $engine.settings.tableMaterial) {
                ForEach(TableMaterial.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Sand", selection: $engine.settings.sandColor) {
                ForEach(SandColor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            HStack {
                Toggle("Daily summary at", isOn: $engine.settings.summaryOn)
                Spacer()
                Picker("", selection: $engine.settings.summaryHour) {
                    ForEach(12..<24, id: \.self) { Text(String(format: "%02d:%02d", $0, engine.settings.summaryMinute)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 80)
                .disabled(!engine.settings.summaryOn)
            }
            Toggle("Show in Dock & ⌘-Tab", isOn: $engine.settings.showInDock)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in engine.launchAtLogin = v }
            if !engine.notificationsAllowed {
                Label("Notifications are off — enable Pomo in System Settings › Notifications.", systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Quit Pomo") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// "+3 / +5 / +10 min": stay in the flow a little longer. Right after a phase ends it steps back into it.
struct ExtendRow: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 8) {
            Text("More \(engine.extendTarget.title.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach([3, 5, 10], id: \.self) { m in
                Button("+\(m)m") { engine.extend(minutes: m) }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .foregroundStyle(engine.extendTarget.tint)
                    .background(engine.extendTarget.tint.opacity(0.13), in: Capsule())
                    .help("Add \(m) minutes to this \(engine.extendTarget.title.lowercased())")
            }
        }
    }
}

struct MusicRow: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        @Bindable var music = engine.audio
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { engine.toggleMusic() } label: {
                    Image(systemName: engine.audioOn ? (music.isTalks ? "megaphone.fill" : "music.note") : "speaker.slash.fill")
                        .foregroundStyle(engine.audioOn ? engine.phase.tint : .secondary)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .help(music.isTalks ? (engine.audioOn ? "Motivational talks off" : "Motivational talks on")
                                    : (engine.audioOn ? "Music off" : "Music on"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(music.current?.title ?? (music.status.isEmpty ? placeholder(music) : music.status))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let c = music.current {
                        Text("\(music.isPlaying ? "Playing" : "Paused") · \(c.minutes / 60 > 0 ? "\(c.minutes / 60)h " : "")\(c.minutes % 60)m")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if Screenshots.isActive {   // native menus can't be rendered to an image
                    Text(music.mood).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Menu {
                        Picker("Mood", selection: $music.mood) {
                            Text("Mix (all moods)").tag("Mix")
                            ForEach(music.moods, id: \.name) { Text($0.name).tag($0.name) }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Button("Open in YouTube") { music.openInBrowser() }.disabled(music.current == nil)
                    } label: {
                        Text(music.mood).font(.caption2)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Button {
                    let m = music
                    Task { m.forget(); await m.shuffle(); if engine.audioOn && engine.isRunning { m.play() } }
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.plain)
                .help(music.isTalks ? "Another talk" : "Play something else")
                Button { engine.settings.showPlayer.toggle() } label: {
                    Image(systemName: engine.settings.showPlayer ? "play.rectangle.fill" : "play.rectangle")
                        .foregroundStyle(engine.settings.showPlayer ? engine.phase.tint : .secondary)
                }
                .buttonStyle(.plain)
                .help(engine.settings.showPlayer ? "Hide the video player (sound keeps playing)" : "Show the video player")
            }
            if let r = music.raga ?? (music.mood == RagaClock.moodName && music.current == nil ? RagaClock.ragas(at: Calendar.current.component(.hour, from: Date())).first : nil) {
                Label(r.note, systemImage: "sun.horizon")
                    .font(.caption2)
                    .foregroundStyle(engine.phase.tint)
                    .lineLimit(1)
                    .help("Raga of the hour: chosen by the traditional time of day for each raga")
            }
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                if Screenshots.isActive {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 3)
                        .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(engine.phase.tint).frame(width: g.size.width * music.volume / 100, height: 3) } }
                } else {
                    Slider(value: $music.volume, in: 0...100).controlSize(.mini)
                }
                Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func placeholder(_ m: Music) -> String {
        if m.isTalks { return engine.audioOn ? "A motivational talk plays during the break" : "Motivational talks are off" }
        return "Music starts with your next focus block"
    }
}
