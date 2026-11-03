import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

enum Phase: String, Codable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    var quoteKind: String { self == .focus ? "focus" : "rest" }
    var symbol: String { self == .focus ? "flame.fill" : "cup.and.saucer.fill" }
}

struct Session: Codable, Identifiable {
    var id = UUID()
    let end: Date
    let minutes: Int
    let intention: String
}

struct Settings: Codable, Equatable {
    var focusMin = 25
    var shortMin = 5
    var longMin = 15
    var longEvery = 4
    var autoStartBreaks = true
    var autoStartFocus = true
    var quotesOn = true
    var miniTimerOn = true
    var musicOn = true
    var breakTalksOn = true
    var plantOn = true
    var quoteOnWidget = true
    var showInDock = true
    var widgetScale: Double = 1.0
    var frameMaterial: FrameMaterial = .brass
    var tableMaterial: TableMaterial = .walnut
    var sandColor: SandColor = .golden
    var decor: Decor { Decor(frame: frameMaterial, table: tableMaterial, sand: sandColor) }
    var showPlayer = true
    var youtubeAPIKey = ""
    var summaryOn = true
    var summaryHour = 18
    var summaryMinute = 30

    init() {}

    /// Missing keys fall back to defaults, so adding a setting never wipes saved preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        focusMin = try c.decodeIfPresent(Int.self, forKey: .focusMin) ?? d.focusMin
        shortMin = try c.decodeIfPresent(Int.self, forKey: .shortMin) ?? d.shortMin
        longMin = try c.decodeIfPresent(Int.self, forKey: .longMin) ?? d.longMin
        longEvery = try c.decodeIfPresent(Int.self, forKey: .longEvery) ?? d.longEvery
        autoStartBreaks = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? d.autoStartBreaks
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
        quotesOn = try c.decodeIfPresent(Bool.self, forKey: .quotesOn) ?? d.quotesOn
        miniTimerOn = try c.decodeIfPresent(Bool.self, forKey: .miniTimerOn) ?? d.miniTimerOn
        musicOn = try c.decodeIfPresent(Bool.self, forKey: .musicOn) ?? d.musicOn
        breakTalksOn = try c.decodeIfPresent(Bool.self, forKey: .breakTalksOn) ?? d.breakTalksOn
        plantOn = try c.decodeIfPresent(Bool.self, forKey: .plantOn) ?? d.plantOn
        quoteOnWidget = try c.decodeIfPresent(Bool.self, forKey: .quoteOnWidget) ?? d.quoteOnWidget
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        widgetScale = try c.decodeIfPresent(Double.self, forKey: .widgetScale) ?? d.widgetScale
        frameMaterial = (try? c.decodeIfPresent(FrameMaterial.self, forKey: .frameMaterial)) ?? d.frameMaterial
        tableMaterial = (try? c.decodeIfPresent(TableMaterial.self, forKey: .tableMaterial)) ?? d.tableMaterial
        sandColor = (try? c.decodeIfPresent(SandColor.self, forKey: .sandColor)) ?? d.sandColor
        showPlayer = try c.decodeIfPresent(Bool.self, forKey: .showPlayer) ?? d.showPlayer
        youtubeAPIKey = try c.decodeIfPresent(String.self, forKey: .youtubeAPIKey) ?? d.youtubeAPIKey
        summaryOn = try c.decodeIfPresent(Bool.self, forKey: .summaryOn) ?? d.summaryOn
        summaryHour = try c.decodeIfPresent(Int.self, forKey: .summaryHour) ?? d.summaryHour
        summaryMinute = try c.decodeIfPresent(Int.self, forKey: .summaryMinute) ?? d.summaryMinute
    }
}

/// Single source of truth. Time is derived from `endDate`, never from counting ticks,
/// so sleep/wake and App Nap cannot drift the clock.
@MainActor
@Observable
final class Engine {
    static let shared = Engine()

    private(set) var phase: Phase = .focus
    private(set) var isRunning = false
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    /// Total length of the current run including any +N extensions; nil = the phase's normal duration.
    private(set) var phaseLength: TimeInterval?
    /// What the last natural phase end changed, so "+N min" right after it can step back into that phase.
    private var justFinished: Finished?
    private struct Finished { let phase: Phase; let completedInCycle: Int; let intention: String; let length: TimeInterval; let logged: UUID?; let at: Date }
    private(set) var completedInCycle = 0
    private(set) var now = Date()
    private(set) var quote: Quote
    private(set) var history: [Session] = []
    var intention = ""
    /// Desk bonsai: lifetime focus blocks (growth) and break discipline (health, 0…1).
    private(set) var plantBlocks = 0
    private(set) var plantHealth = 0.85
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            if settings.showPlayer != oldValue.showPlayer { Music.shared.updateHost(); Music.talks.updateHost() }
        }
    }
    var notificationsAllowed = true

    private let defaults = UserDefaults.standard
    private let bag = QuoteBag()
    private var ticker: Timer?
    private var activity: NSObjectProtocol?
    private static let notifID = "pomo.phase-end"

    private init() {
        settings = (defaults.data(forKey: "settings")).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        quote = bag.next("focus")
        history = (defaults.data(forKey: "history")).flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []
        completedInCycle = defaults.integer(forKey: "completedInCycle")
        // First run with the plant: seed its growth from the history we already have.
        plantBlocks = defaults.object(forKey: "plant.blocks") as? Int ?? history.count
        plantHealth = defaults.object(forKey: "plant.health") as? Double ?? 0.85
        if !Screenshots.isActive && defaults.object(forKey: "plant.blocks") == nil {
            defaults.set(plantBlocks, forKey: "plant.blocks")
            defaults.set(plantHealth, forKey: "plant.health")
        }
        if let saved = defaults.string(forKey: "phase"), let p = Phase(rawValue: saved) { phase = p }
        // Resume a run that was in flight when the app quit or the Mac restarted.
        if !Screenshots.isActive, let end = defaults.object(forKey: "endDate") as? Date {
            endDate = end
            isRunning = true
            intention = defaults.string(forKey: "intention") ?? ""
            if let len = defaults.object(forKey: "phaseLength") as? Double { phaseLength = len }
            startTicker()
            playAudio()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { Engine.shared.tick() } }
        writeState()
    }

    // MARK: derived

    func duration(of p: Phase) -> TimeInterval {
        let m: Int = switch p {
        case .focus: settings.focusMin
        case .shortBreak: settings.shortMin
        case .longBreak: settings.longMin
        }
        return TimeInterval(m * 60)
    }

    var remaining: TimeInterval {
        if let end = endDate, isRunning { return max(0, end.timeIntervalSince(now)) }
        return pausedRemaining ?? duration(of: phase)
    }

    var length: TimeInterval { phaseLength ?? duration(of: phase) }
    var progress: Double { 1 - remaining / length }
    var isIdle: Bool { !isRunning && pausedRemaining == nil }

    var clock: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var today: [Session] { history.filter { Calendar.current.isDateInToday($0.end) } }
    var todayMinutes: Int { today.reduce(0) { $0 + $1.minutes } }

    /// Average pomodoros/day over the 7 days before today (days with zero count too).
    var sevenDayAverage: Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let from = cal.date(byAdding: .day, value: -7, to: start) else { return 0 }
        return Double(history.filter { $0.end >= from && $0.end < start }.count) / 7
    }

    // MARK: controls

    func start() { start(audioDelay: 0) }

    private func start(audioDelay: TimeInterval) {
        guard !isRunning else { return }
        let left = pausedRemaining ?? duration(of: phase)
        if phaseLength == nil { phaseLength = duration(of: phase) }
        endDate = Date().addingTimeInterval(left)
        pausedRemaining = nil
        isRunning = true
        scheduleNotification(in: left)
        startTicker()
        playAudio(delay: audioDelay)
        persist()
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining
        endDate = nil
        isRunning = false
        cancelNotification()
        stopTicker()
        Music.stopAll()
        persist()
    }

    /// Focus music during focus, a motivational talk during breaks — each only if switched on.
    private func playAudio(delay: TimeInterval = 0) {
        guard isRunning else { return }
        if phase == .focus {
            Music.talks.pause()
            if settings.musicOn { Music.shared.play() }
        } else if settings.breakTalksOn {
            Music.shared.pause()
            guard delay > 0 else { Music.talks.play(); return }
            // Let the gong ring out before the speaker starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    let e = Engine.shared
                    if e.isRunning && e.phase != .focus && e.settings.breakTalksOn { Music.talks.play() }
                }
            }
        }
    }

    // MARK: snooze / extend

    /// Which phase "+N min" would lengthen right now: the one that just ended (for 5 min after it ended),
    /// otherwise the one that is running.
    var extendTarget: Phase {
        if let f = justFinished, now.timeIntervalSince(f.at) < 300 { return f.phase }
        return phase
    }

    /// "I'm in the middle of something": add minutes. Just after a phase ended this steps back into it
    /// (undoing the switch); otherwise it lengthens the current phase.
    func extend(minutes: Int, stepBackWithin window: TimeInterval = 300) {
        let add = TimeInterval(max(1, minutes) * 60)
        if let f = justFinished, Date().timeIntervalSince(f.at) < window {
            justFinished = nil
            cancelNotification()
            Music.stopAll()
            stopTicker()
            if let id = f.logged { history.removeAll { $0.id == id }; plantBlocks -= 1 }   // re-logged with the extra time when it ends
            if f.phase != .focus { tendPlant(-0.15) }   // undo the break's nourishment; it's counted again when it ends
            phase = f.phase
            completedInCycle = f.completedInCycle
            intention = f.intention
            phaseLength = f.length + add
            isRunning = false
            endDate = nil
            pausedRemaining = add
            start()
            return
        }
        phaseLength = length + add
        if isRunning, let end = endDate {
            endDate = end.addingTimeInterval(add)
            scheduleNotification(in: remaining)
        } else {
            pausedRemaining = (pausedRemaining ?? duration(of: phase)) + add
        }
        persist()
        writeState()
    }

    /// Show/hide the floating hourglass (⌃⌥P, hover button, window header, `pomo hide|show`). Timer keeps running.
    func toggleWidget() { settings.miniTimerOn.toggle() }

    /// Music on/off from the pill or window; remembered for the next focus blocks too.
    /// During breaks the same button switches the motivational talks instead.
    func toggleMusic() {
        if phase == .focus {
            settings.musicOn.toggle()
            if settings.musicOn && isRunning { Music.shared.play() } else { Music.shared.pause() }
        } else {
            settings.breakTalksOn.toggle()
            if settings.breakTalksOn && isRunning { Music.talks.play() } else { Music.talks.pause() }
        }
    }

    var audioOn: Bool { phase == .focus ? settings.musicOn : settings.breakTalksOn }
    var audio: Music { phase == .focus ? Music.shared : Music.talks }

    func toggle() { isRunning ? pause() : start() }

    /// Skip ends the current phase without logging it.
    func skip() {
        justFinished = nil
        if phase != .focus { tendPlant(-0.18) }   // cutting a break short wilts the plant a little
        cancelNotification()
        advance(logCompleted: false)
    }

    func reset() {
        cancelNotification()
        Music.stopAll()
        stopTicker()
        isRunning = false
        endDate = nil
        pausedRemaining = nil
        phaseLength = nil
        justFinished = nil
        phase = .focus
        completedInCycle = 0
        intention = ""
        quote = settings.quotesOn ? bag.next("focus") : quote
        persist()
    }

    // MARK: clock

    func tick() {
        now = Date()
        if isRunning, let end = endDate, now >= end {
            // The OS already delivered the (silent) scheduled notification; sound is played in advance().
            advance(logCompleted: true)
        }
        maybeSendDailySummary()
        writeState()
    }

    /// Set by the app delegate: bring the window forward so the break is visible.
    var onBreakStart: (() -> Void)?
    private var player: NSSound?

    /// Gong = focus block finished. Singing bowl = next focus block begins.
    private func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        player?.stop()
        player = NSSound(contentsOf: url, byReference: true)
        player?.play()
    }

    private func advance(logCompleted: Bool) {
        let finished = phase
        let before = (cycle: completedInCycle, intention: intention, length: length)
        var logged: UUID?
        Music.stopAll()
        if finished == .focus && logCompleted { play("Gong") }
        if finished != .focus { play("Bowl") }
        if finished == .focus && logCompleted {
            let session = Session(end: Date(), minutes: Int((length / 60).rounded()), intention: intention)
            logged = session.id
            history.append(session)
            plantBlocks += 1
            let cutoff = Date().addingTimeInterval(-60 * 86400)
            history.removeAll { $0.end < cutoff }
        }
        if finished != .focus && logCompleted { tendPlant(0.15) }   // a full break nourishes it
        justFinished = logCompleted
            ? Finished(phase: finished, completedInCycle: before.cycle, intention: before.intention, length: before.length, logged: logged, at: Date())
            : nil
        Music.talks.forget()   // every break gets a fresh talk
        if finished == .focus {
            completedInCycle += 1
            phase = completedInCycle % max(1, settings.longEvery) == 0 ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak { completedInCycle = 0 }
            phase = .focus
            intention = ""
        }
        if settings.quotesOn { quote = consumePendingQuote() ?? bag.next(phase.quoteKind) }
        isRunning = false
        endDate = nil
        pausedRemaining = nil
        phaseLength = nil
        stopTicker()
        let auto = phase == .focus ? settings.autoStartFocus : settings.autoStartBreaks
        if auto { start(audioDelay: phase == .focus ? 0 : 4) } else { persist() }
        if finished == .focus && logCompleted { onBreakStart?() }
    }

    private func startTicker() {
        stopTicker()
        now = Date()
        // Keep the 1 s tick honest while a phase runs; App Nap would otherwise coalesce it.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Pomodoro running")
        let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { Engine.shared.tick() } }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        now = Date()
    }

    // MARK: notifications

    /// One notification per phase, scheduled up front so it fires on time even if the app is throttled.
    /// Its body carries the quote that the *next* phase will show, so the card and the banner always agree.
    private func scheduleNotification(in seconds: TimeInterval) {
        cancelNotification()
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        let next = upcomingPhase
        switch phase {
        case .focus:
            content.title = "Focus block done"
            content.subtitle = intention.isEmpty ? "Time for a \(next.title.lowercased())." : "“\(intention)” — time for a \(next.title.lowercased())."
        case .shortBreak, .longBreak:
            content.title = "Break's over — back to it"
            content.subtitle = "Next: \(Int(duration(of: .focus) / 60)) min focus"
        }
        if settings.quotesOn {
            let q = bag.next(next.quoteKind)
            pendingQuote = q
            content.body = "\(q.text) — \(q.author)"
        }
        content.categoryIdentifier = "PHASE_END"
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notifID, content: content, trigger: trigger))
    }

    private var pendingQuote: Quote?

    private var upcomingPhase: Phase {
        if phase != .focus { return .focus }
        return (completedInCycle + 1) % max(1, settings.longEvery) == 0 ? .longBreak : .shortBreak
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notifID])
        pendingQuote = nil
    }

    /// Called from `advance`: prefer the quote already shown in the banner.
    func consumePendingQuote() -> Quote? { defer { pendingQuote = nil }; return pendingQuote }

    private func maybeSendDailySummary() {
        guard settings.summaryOn, !today.isEmpty else { return }
        let cal = Calendar.current
        let key = "summarySent"
        let todayKey = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        guard defaults.string(forKey: key) != todayKey else { return }
        let c = cal.dateComponents([.hour, .minute], from: now)
        guard (c.hour ?? 0, c.minute ?? 0) >= (settings.summaryHour, settings.summaryMinute) else { return }
        defaults.set(todayKey, forKey: key)

        let content = UNMutableNotificationContent()
        let h = todayMinutes / 60, m = todayMinutes % 60
        content.title = "Today: \(today.count) pomodoro\(today.count == 1 ? "" : "s") · \(h > 0 ? "\(h)h " : "")\(m)m focused"
        content.subtitle = String(format: "7-day average: %.1f / day", sevenDayAverage)
        let intents = today.map(\.intention).filter { !$0.isEmpty }
        content.body = intents.isEmpty ? "Good work. Shut it down properly — tomorrow starts tonight." : "You worked on: " + intents.joined(separator: " · ")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pomo.summary", content: content, trigger: nil))
    }

    // MARK: persistence

    private func tendPlant(_ delta: Double) {
        plantHealth = min(1, max(0, plantHealth + delta))
    }

    private func persist() {
        guard !Screenshots.isActive else { return }
        defaults.set(plantBlocks, forKey: "plant.blocks")
        defaults.set(plantHealth, forKey: "plant.health")
        defaults.set(phase.rawValue, forKey: "phase")
        defaults.set(completedInCycle, forKey: "completedInCycle")
        defaults.set(isRunning ? endDate : nil, forKey: "endDate")
        defaults.set(phaseLength, forKey: "phaseLength")
        defaults.set(intention, forKey: "intention")
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "history") }
        writeState()
    }

    private func saveSettings() {
        guard !Screenshots.isActive else { return }
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings") }
    }

    /// Plain key=value snapshot for the `pomo status` CLI.
    private func writeState() {
        guard !Screenshots.isActive else { return }
        let state = """
        phase=\(phase.rawValue)
        running=\(isRunning)
        paused=\(pausedRemaining != nil)
        remaining=\(clock)
        intention=\(intention)
        today=\(today.count)
        minutes=\(todayMinutes)
        music=\(audio.isPlaying ? "▶ " : "")\(audio.current?.title ?? audio.status)
        """
        try? state.write(to: Paths.support.appendingPathComponent("state"), atomically: true, encoding: .utf8)
    }

    // MARK: screenshot mode (in-memory only; persist/writeState are no-ops while it is active)

    func demoPlant(blocks: Int, health: Double) { plantBlocks = blocks; plantHealth = health }

    func demo(phase: Phase, progress: Double, running: Bool, intention: String, today: Int) {
        self.phase = phase
        self.intention = intention
        settings = Settings()   // README images show defaults, not this Mac's preferences (not saved in this mode)
        now = Date()
        let remaining = duration(of: phase) * (1 - progress)
        isRunning = running
        endDate = running ? now.addingTimeInterval(remaining) : nil
        pausedRemaining = running ? nil : remaining
        completedInCycle = 2
        plantBlocks = 34
        plantHealth = 0.9
        let todays = (0..<today).map { Session(end: Date().addingTimeInterval(Double(-$0) * 1800), minutes: 25, intention: "") }
        let week = [6, 4, 7, 5, 8, 3, 6].enumerated().flatMap { day, n in
            (0..<n).map { Session(end: Date().addingTimeInterval(-Double(day + 1) * 86400 - Double($0) * 1800), minutes: 25, intention: "") }
        }
        history = todays + week
        quote = Quote(text: "How we spend our days is, of course, how we spend our lives.", author: "Annie Dillard, The Writing Life")
    }

    // MARK: launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {
                NSLog("Pomo: launch-at-login change failed: \(error)")
            }
        }
    }

    // MARK: URL control  (pomo://start?intent=..., pause, resume, toggle, skip, reset)

    func handle(url: URL) {
        guard url.scheme == "pomo" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let intent = items.first(where: { $0.name == "intent" })?.value, !intent.isEmpty, phase == .focus {
            intention = intent
        }
        switch url.host ?? "" {
        case "start", "resume": start()
        case "pause": pause()
        case "toggle": toggle()
        case "skip": skip()
        case "extend", "snooze":
            let m = items.first(where: { $0.name == "min" })?.value.flatMap(Int.init) ?? 5
            extend(minutes: min(max(m, 1), 60))
        case "reset": reset()
        case "hide": settings.miniTimerOn = false
        case "show": settings.miniTimerOn = true
        case "widget": toggleWidget()
        case "video":
            switch items.first(where: { $0.name == "value" })?.value {
            case "on": settings.showPlayer = true
            case "off": settings.showPlayer = false
            default: settings.showPlayer.toggle()
            }
        case "size":
            if let v = items.first(where: { $0.name == "value" })?.value, let pct = Double(v) {
                settings.widgetScale = min(max(pct / 100, MiniTimerView.sizeRange.lowerBound), MiniTimerView.sizeRange.upperBound)
            }
        default: break
        }
        writeState()
    }
}
