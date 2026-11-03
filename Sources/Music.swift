import AppKit
import Foundation
import Observation
import SwiftUI
import WebKit

/// Focus music from YouTube: pick a mood, search YouTube for long sets/ambiences, play one at random
/// in YouTube's embedded player (a small floating window the user may hide) that follows the timer.
struct Mood: Codable, Hashable {
    let name: String
    let queries: [String]
}

struct Track: Codable, Hashable {
    let id: String
    let title: String
    let minutes: Int
}

enum MusicLibrary {
    /// Edit by dropping `music.json` (an array of {"name": .., "queries": [..]}) into Application Support/Pomo.
    static let defaults: [Mood] = [
        Mood(name: "Nature", queries: [
            "flowing river stream sounds forest birds", "ocean waves sounds for focus",
            "forest stream ambience no music", "rainforest sounds for studying",
        ]),
        Mood(name: "Bansuri & flute", queries: [
            "bansuri flute meditation music", "Hariprasad Chaurasia bansuri raga", "indian flute music for focus",
        ]),
        // Queries come from RagaClock at play time: the raga that fits the hour.
        Mood(name: RagaClock.moodName, queries: []),
        Mood(name: "Shamanic", queries: [
            "shamanic flute drum meditation music", "shamanic handpan journey music",
        ]),
        Mood(name: "Sunset sets", queries: [
            "Miss Monique Sunset Yacht Ibiza", "Ibiza Sunrise Melodic House Set Afterglow",
            "melodic techno sunset dj set", "progressive psytrance dj set",
        ]),
    ]

    /// Break-time talks: short motivational speeches (edit via `talks.json`).
    static let talks: [Mood] = [
        Mood(name: "Discipline", queries: [
            "discipline motivational speech", "Jocko Willink discipline equals freedom speech",
            "David Goggins motivational speech", "stay hard motivation speech", "Eric Thomas motivational speech",
        ]),
        Mood(name: "Run every day", queries: [
            "why you should run every day motivation", "running motivation speech", "morning run motivational speech",
        ]),
        Mood(name: "Mindset", queries: [
            "Kobe Bryant mamba mentality speech", "Les Brown motivational speech", "stoic discipline motivation speech",
            "Denzel Washington motivational speech", "keep going motivational speech 5 minutes",
        ]),
    ]

    static func load(_ file: String = "music.json", fallback: [Mood] = defaults) -> [Mood] {
        let url = Paths.support.appendingPathComponent(file)
        if let data = try? Data(contentsOf: url), let moods = try? JSONDecoder().decode([Mood].self, from: data), !moods.isEmpty {
            return moods
        }
        return fallback
    }
}

/// Search goes through the official YouTube Data API when the user has added an API key in Settings;
/// without one it falls back to reading the public results page. Results are cached per query for 3 days.
enum YouTubeSearch {
    /// Returns every video with a known length; callers filter by the length they want.
    @MainActor static func search(_ query: String) async -> [Track] {
        let apiKey = Engine.shared.settings.youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey.isEmpty ? await resultsPage(query) : await api(query, key: apiKey)
    }

    /// YouTube Data API v3: search.list (100 units) + videos.list for durations (1 unit). The free daily
    /// quota (10,000 units) covers ~100 uncached searches a day; with the cache, far more than Pomo needs.
    static func api(_ query: String, key apiKey: String) async -> [Track] {
        let key = "ytapi.cache.\(query)"
        if let cached = cached(key) { return cached }
        var s = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        s.queryItems = [.init(name: "part", value: "snippet"), .init(name: "type", value: "video"),
                        .init(name: "videoEmbeddable", value: "true"), .init(name: "maxResults", value: "25"),
                        .init(name: "q", value: query), .init(name: "key", value: apiKey)]
        guard let found = await json(s.url!), let items = found["items"] as? [[String: Any]] else { return [] }
        var titles: [String: String] = [:]
        for item in items {
            if let id = (item["id"] as? [String: Any])?["videoId"] as? String,
               let title = (item["snippet"] as? [String: Any])?["title"] as? String { titles[id] = unescape(title) }
        }
        guard !titles.isEmpty else { return [] }
        var v = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        v.queryItems = [.init(name: "part", value: "contentDetails"), .init(name: "id", value: titles.keys.joined(separator: ",")),
                        .init(name: "key", value: apiKey)]
        guard let details = await json(v.url!), let vids = details["items"] as? [[String: Any]] else { return [] }
        let tracks: [Track] = vids.compactMap { item in
            guard let id = item["id"] as? String, let title = titles[id],
                  let iso = (item["contentDetails"] as? [String: Any])?["duration"] as? String else { return nil }
            let mins = isoMinutes(iso)
            return mins > 0 ? Track(id: id, title: title, minutes: mins) : nil
        }
        store(tracks, key)
        return tracks
    }

    private static func json(_ url: URL) async -> [String: Any]? {
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// "PT1H2M10S" → 62, "PT4M30S" → 4, "PT45S" → 1.
    static func isoMinutes(_ s: String) -> Int {
        var h = 0, m = 0, sec = 0, n = 0
        for ch in s {
            if let d = ch.wholeNumberValue { n = n * 10 + d; continue }
            switch ch { case "H": h = n; case "M": m = n; case "S": sec = n; default: break }
            n = 0
        }
        return h * 60 + m + (h == 0 && m == 0 && sec > 0 ? 1 : 0)
    }

    private static func unescape(_ s: String) -> String {
        [("&amp;", "&"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">")]
            .reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static func cached(_ key: String) -> [Track]? {
        guard let blob = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(Cached.self, from: blob),
              Date().timeIntervalSince(c.at) < 3 * 86400, !c.tracks.isEmpty else { return nil }
        return c.tracks
    }

    private static func store(_ tracks: [Track], _ key: String) {
        if !tracks.isEmpty, let blob = try? JSONEncoder().encode(Cached(at: Date(), tracks: tracks)) {
            UserDefaults.standard.set(blob, forKey: key)
        }
    }

    /// No-key fallback: the public results page.
    static func resultsPage(_ query: String) async -> [Track] {
        let key = "yt2.cache.\(query)"
        if let blob = UserDefaults.standard.data(forKey: key),
           let cached = try? JSONDecoder().decode(Cached.self, from: blob),
           Date().timeIntervalSince(cached.at) < 3 * 86400, !cached.tracks.isEmpty {
            return cached.tracks
        }
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return [] }
        let tracks = parse(html)
        if !tracks.isEmpty, let blob = try? JSONEncoder().encode(Cached(at: Date(), tracks: tracks)) {
            UserDefaults.standard.set(blob, forKey: key)
        }
        return tracks
    }

    private struct Cached: Codable { let at: Date; let tracks: [Track] }

    static func parse(_ html: String) -> [Track] {
        guard let start = html.range(of: "var ytInitialData = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let data = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [Track] = []
        func walk(_ o: Any) {
            if let d = o as? [String: Any] {
                if let v = d["videoRenderer"] as? [String: Any], let id = v["videoId"] as? String {
                    let runs = ((v["title"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
                    let title = runs.compactMap { $0["text"] as? String }.joined()
                    let length = (v["lengthText"] as? [String: Any])?["simpleText"] as? String ?? ""
                    let mins = minutes(length)
                    if mins > 0 { out.append(Track(id: id, title: title, minutes: mins)) }
                }
                d.values.forEach(walk)
            } else if let a = o as? [Any] {
                a.forEach(walk)
            }
        }
        walk(root)
        return out
    }

    /// "1:02:33" → 62, "45:10" → 45, "4:30" → 4; live streams have no length and are skipped.
    static func minutes(_ s: String) -> Int {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 60 + parts[1]
        case 2: return max(parts[0], parts[1] > 0 ? 1 : 0)
        default: return 0
        }
    }
}

@MainActor
@Observable
final class Music: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    /// Focus music: long sets and ambiences, played during focus blocks.
    static let shared = Music(key: "music", moods: MusicLibrary.load(), lengths: 25...100_000, volume: 45, randomStart: true)
    /// Break talks: 3–15 min motivational speeches, a fresh one each break.
    static let talks = Music(key: "talks", moods: MusicLibrary.load("talks.json", fallback: MusicLibrary.talks),
                             lengths: 3...15, volume: 70, randomStart: false)

    static func stopAll() { shared.pause(); talks.pause() }

    private(set) var current: Track?
    private(set) var isPlaying = false
    private(set) var status = ""
    /// Set when the current track was chosen as the raga of the hour.
    private(set) var raga: Raga?
    let moods: [Mood]
    let isTalks: Bool
    private let key: String
    private let lengths: ClosedRange<Int>
    private let randomStart: Bool

    /// "Mix" picks from every mood.
    var mood: String {
        didSet { if !Screenshots.isActive { UserDefaults.standard.set(mood, forKey: "\(key).mood") } }
    }
    var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "\(key).volume")
            js("setVol(\(Int(volume)))")
        }
    }

    private var web: WKWebView?
    private var host: NSWindow?
    private var ready = false
    private var wantPlaying = false
    private var failures = 0
    private var recent: [String]

    private init(key: String, moods: [Mood], lengths: ClosedRange<Int>, volume: Double, randomStart: Bool) {
        self.key = key
        // Custom music.json files still get the raga clock.
        self.moods = key == "music" && !moods.contains(where: { $0.name == RagaClock.moodName })
            ? moods + [Mood(name: RagaClock.moodName, queries: [])] : moods
        self.lengths = lengths
        self.randomStart = randomStart
        isTalks = key == "talks"
        recent = UserDefaults.standard.stringArray(forKey: "\(key).recent") ?? []
        mood = UserDefaults.standard.string(forKey: "\(key).mood") ?? "Mix"
        self.volume = UserDefaults.standard.object(forKey: "\(key).volume") as? Double ?? volume
        super.init()
    }

    /// Screenshot mode: show a track as playing without loading anything.
    func demo(_ track: Track, raga: Raga? = nil) {
        current = track; isPlaying = true; status = ""; self.raga = raga
        mood = raga == nil ? "Sunset sets" : RagaClock.moodName
    }

    // MARK: controls (called by the engine and the UI)

    /// Focus started or resumed: continue the current track, or find a new one.
    func play() {
        wantPlaying = true
        updateHost()
        if current != nil, ready { js("fadeIn()"); isPlaying = true; return }
        Task { await shuffle() }
    }

    /// Break, pause, skip or reset: fade out and hold the position.
    func pause() {
        wantPlaying = false
        updateHost()
        guard isPlaying else { return }
        js("fadeOut()")
        isPlaying = false
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Drop the current track so the next play() finds a new one (each break starts a fresh talk).
    func forget() {
        pause()
        current = nil
        ready = false
        updateHost()
    }

    private var searching = false

    func shuffle() async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        status = isTalks ? "Finding a talk…" : "Finding something good…"
        let pool = mood == "Mix" ? moods : moods.filter { $0.name == mood }
        guard !pool.isEmpty else { status = "No moods configured"; return }
        // A query can come back with nothing of the right length; try a few before giving up.
        var reached = false
        for _ in 0..<4 {
            guard let m = pool.randomElement() else { break }
            let r: Raga? = m.name == RagaClock.moodName ? RagaClock.pick() : nil
            guard let q = (r?.queries ?? m.queries).randomElement() else { continue }
            let all = await YouTubeSearch.search(q)
            reached = reached || !all.isEmpty
            if let pick = all.filter({ lengths.contains($0.minutes) && !recent.contains($0.id) }).prefix(8).randomElement() {
                raga = r
                load(pick)
                return
            }
        }
        status = reached ? "Nothing new found — try ⇄" : "Couldn't reach YouTube — check your connection"
    }

    func openInBrowser() {
        guard let c = current, let url = URL(string: "https://www.youtube.com/watch?v=\(c.id)") else { return }
        pause()
        NSWorkspace.shared.open(url)
    }

    // MARK: player

    private func load(_ track: Track) {
        current = track
        status = ""
        recent = Array(([track.id] + recent).prefix(30))
        UserDefaults.standard.set(recent, forKey: "\(key).recent")
        ensureWebView()
        ready = false
        // Long ambiences start at a random point so they don't always open the same way.
        let start = randomStart && track.minutes > 90 ? Int.random(in: 0...(track.minutes - 60) * 60) : 0
        web?.loadHTMLString(Self.page(id: track.id, start: start, volume: Int(volume), autoplay: wantPlaying),
                            baseURL: URL(string: "https://pomo.local/"))
        updateHost()
    }

    private static let videoSize = NSSize(width: 356, height: 200)   // YouTube's minimum embed size is 200×200
    private static let barHeight: CGFloat = 28

    private func ensureWebView() {
        guard web == nil else { return }
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .nonPersistent()   // no YouTube cookies kept between launches
        cfg.userContentController.add(self, name: "pomo")
        let size = NSSize(width: Self.videoSize.width, height: Self.videoSize.height + Self.barHeight)
        let w = WKWebView(frame: NSRect(origin: .zero, size: Self.videoSize), configuration: cfg)
        w.navigationDelegate = self
        let bar = NSHostingView(rootView: PlayerBar(music: self))
        bar.frame = NSRect(x: 0, y: Self.videoSize.height, width: size.width, height: Self.barHeight)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.addSubview(w)
        container.addSubview(bar)
        let win = NSPanel(contentRect: NSRect(origin: Self.savedOrigin(size), size: size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.contentView = container
        win.isOpaque = false
        win.backgroundColor = .clear
        win.isMovableByWindowBackground = true
        win.hidesOnDeactivate = false
        win.isExcludedFromWindowsMenu = true
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main) { [weak win] _ in
            MainActor.assumeIsolated {
                if let o = win?.frame.origin { UserDefaults.standard.set([o.x, o.y], forKey: "player.origin") }
            }
        }
        host = win
        web = w
        updateHost()
    }

    /// Default spot: bottom-right of the main screen; afterwards wherever the user dragged it.
    private static func savedOrigin(_ size: NSSize) -> NSPoint {
        if let xy = UserDefaults.standard.array(forKey: "player.origin") as? [Double], xy.count == 2 {
            return NSPoint(x: xy[0], y: xy[1])
        }
        let f = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: f.maxX - size.width - 20, y: f.minY + 20)
    }

    /// The video is shown while something plays (YouTube's embed rules). Hiding it is the user's choice
    /// (Settings or the player's eye button); then the window stays on-screen but transparent and
    /// click-through, because an ordered-out web view stops playing.
    func updateHost() {
        guard let win = host else { return }
        let visible = wantPlaying && current != nil && Engine.shared.settings.showPlayer
        if visible {
            win.alphaValue = 1
            win.ignoresMouseEvents = false
            win.hasShadow = true
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            win.orderFrontRegardless()
        } else {
            win.alphaValue = 0
            win.ignoresMouseEvents = true
            win.hasShadow = false
            win.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            // Excluded from Mission Control / Exposé / window cycling while invisible.
            win.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
            win.orderBack(nil)
        }
    }

    private func js(_ code: String) {
        web?.evaluateJavaScript(code, completionHandler: nil)
    }

    nonisolated func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { handle(message.body as? String ?? "") }
    }

    private func handle(_ event: String) {
        switch event {
        case "ready":
            ready = true
            failures = 0
            if wantPlaying { js("fadeIn()"); isPlaying = true }
        case "ended":
            Task { await shuffle() }
        case let e where e.hasPrefix("error"):
            // 101/150 = owner disabled embedding, 100 = removed. Try another, then give up gracefully.
            failures += 1
            isPlaying = false
            if failures < 5 { Task { await shuffle() } } else { status = "YouTube refused to play — try ⇄ or open in browser" }
        default:
            break
        }
    }

    private static func page(id: String, start: Int, volume: Int, autoplay: Bool) -> String {
        """
        <!doctype html><html><body style="margin:0;background:#000">
        <div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        let player, target = \(volume), fader;
        const post = m => window.webkit.messageHandlers.pomo.postMessage(m);
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', {
            host: 'https://www.youtube-nocookie.com',
            width: 320, height: 180, videoId: '\(id)',
            playerVars: { autoplay: \(autoplay ? 1 : 0), start: \(start), controls: 0, playsinline: 1, rel: 0 },
            events: {
              onReady: () => { player.setVolume(0); post('ready'); },
              onStateChange: e => { if (e.data === YT.PlayerState.ENDED) post('ended'); },
              onError: e => post('error ' + e.data)
            }
          });
        }
        function ramp(to, ms, done) {
          clearInterval(fader);
          let v = player.getVolume(), steps = 20, i = 0, d = (to - v) / steps;
          fader = setInterval(() => { i++; player.setVolume(Math.round(v + d * i)); if (i >= steps) { clearInterval(fader); done && done(); } }, ms / steps);
        }
        function fadeIn() { if (!player) return; player.playVideo(); ramp(target, 2500); }
        function fadeOut() { if (!player) return; ramp(0, 1500, () => player.pauseVideo()); }
        function setVol(v) { target = v; if (player && player.getPlayerState() === 1) player.setVolume(v); }
        </script></body></html>
        """
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { status = "Player failed to load" }
    }
}

/// Title strip above the video: what's playing, open on YouTube, hide the video.
private struct PlayerBar: View {
    let music: Music
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: music.isTalks ? "megaphone.fill" : "music.note")
                .foregroundStyle(.white.opacity(0.7))
            Text(music.current?.title ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 4)
            Button { music.openInBrowser() } label: { Image(systemName: "arrow.up.right.square") }
                .help("Open on YouTube")
            Button { Engine.shared.settings.showPlayer = false } label: { Image(systemName: "eye.slash") }
                .help("Hide the video (sound keeps playing) · bring it back from the Pomo window")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.8))
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.1))
    }
}
