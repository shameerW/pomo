import Foundation

/// Raga of the hour: Hindustani ragas belong to a time of day (samay). This picks one that fits now
/// and searches YouTube for bansuri / flute renditions of it.
struct Raga: Hashable {
    let name: String
    let time: String
    let mood: String

    var note: String { "\(name) · \(time) raga · \(mood)" }
    var queries: [String] { ["raga \(name) bansuri", "raga \(name) Hariprasad Chaurasia", "raag \(name) flute"] }
}

enum RagaClock {
    static let moodName = "Raga of the hour"

    /// Hour slots (local time, start hour inclusive) and the ragas traditionally sung or played then.
    private static let slots: [(from: Int, ragas: [Raga])] = [
        (1, [Raga(name: "Malkauns", time: "late-night", mood: "deep, meditative"),
             Raga(name: "Darbari", time: "late-night", mood: "grave, majestic")]),
        (4, [Raga(name: "Bhairav", time: "dawn", mood: "solemn, devotional"),
             Raga(name: "Lalit", time: "dawn", mood: "yearning, mystical")]),
        (6, [Raga(name: "Ahir Bhairav", time: "early-morning", mood: "peaceful, devotional"),
             Raga(name: "Todi", time: "morning", mood: "tender, contemplative"),
             Raga(name: "Bilaskhani Todi", time: "morning", mood: "poignant, introspective")]),
        (9, [Raga(name: "Jaunpuri", time: "late-morning", mood: "earnest, serene")]),
        (12, [Raga(name: "Brindavani Sarang", time: "midday", mood: "bright, cooling"),
              Raga(name: "Bhimpalasi", time: "afternoon", mood: "longing, gentle")]),
        (15, [Raga(name: "Multani", time: "late-afternoon", mood: "intense, meditative"),
              Raga(name: "Bhimpalasi", time: "afternoon", mood: "longing, gentle")]),
        (17, [Raga(name: "Marwa", time: "sunset", mood: "restless, profound"),
              Raga(name: "Puriya Dhanashree", time: "sunset", mood: "devotional, wistful")]),
        (19, [Raga(name: "Yaman", time: "evening", mood: "serene, devotional")]),
        (22, [Raga(name: "Bageshree", time: "night", mood: "romantic, longing"),
              Raga(name: "Darbari", time: "night", mood: "grave, majestic"),
              Raga(name: "Malkauns", time: "night", mood: "deep, meditative")]),
    ]

    /// The ragas for an hour (0–23). Hours before 1:00 belong to the night slot.
    static func ragas(at hour: Int) -> [Raga] {
        (slots.last { hour >= $0.from } ?? slots.last!).ragas
    }

    static func pick(at date: Date = Date()) -> Raga {
        ragas(at: Calendar.current.component(.hour, from: date)).randomElement()!
    }
}
