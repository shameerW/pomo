import Foundation

struct Quote: Codable, Hashable {
    let text: String
    let author: String
}

/// Curated quotes with attributions checked against their source works.
/// Override by dropping a `quotes.json` ({"focus": [...], "rest": [...]}) into Application Support/Pomo.
enum QuoteLibrary {
    static let focus: [Quote] = [
        Quote(text: "How we spend our days is, of course, how we spend our lives.", author: "Annie Dillard, The Writing Life"),
        Quote(text: "It is not that we have a short time to live, but that we waste a lot of it.", author: "Seneca, On the Shortness of Life"),
        Quote(text: "Begin at once to live, and count each separate day as a separate life.", author: "Seneca, Letters to Lucilius"),
        Quote(text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius, Meditations"),
        Quote(text: "The impediment to action advances action. What stands in the way becomes the way.", author: "Marcus Aurelius, Meditations"),
        Quote(text: "If you want to improve, be content to be thought foolish and stupid.", author: "Epictetus, Enchiridion"),
        Quote(text: "Well begun is half done.", author: "Aristotle, Politics"),
        Quote(text: "Who you are, what you think, feel, and do, what you love — is the sum of what you focus on.", author: "Winifred Gallagher, Rapt"),
        Quote(text: "Clarity about what matters provides clarity about what does not.", author: "Cal Newport, Deep Work"),
        Quote(text: "Amateurs sit and wait for inspiration, the rest of us just get up and go to work.", author: "Stephen King, On Writing"),
        Quote(text: "People think focus means saying yes to the thing you've got to focus on. But that's not what it means at all. It means saying no to the hundred other good ideas.", author: "Steve Jobs, WWDC 1997"),
        Quote(text: "You do not rise to the level of your goals. You fall to the level of your systems.", author: "James Clear, Atomic Habits"),
        Quote(text: "Every action you take is a vote for the type of person you wish to become.", author: "James Clear, Atomic Habits"),
        Quote(text: "Discipline equals freedom.", author: "Jocko Willink"),
        Quote(text: "Hard choices, easy life. Easy choices, hard life.", author: "Jerzy Gregorek"),
        Quote(text: "The best way out is always through.", author: "Robert Frost, A Servant to Servants"),
        Quote(text: "Lost time is never found again.", author: "Benjamin Franklin, Poor Richard's Almanack"),
        Quote(text: "Dost thou love life? Then do not squander time, for that's the stuff life is made of.", author: "Benjamin Franklin, Poor Richard's Almanack"),
        Quote(text: "Genius is one per cent inspiration and ninety-nine per cent perspiration.", author: "Thomas Edison"),
        Quote(text: "Simplicity is prerequisite for reliability.", author: "Edsger W. Dijkstra"),
        Quote(text: "Premature optimization is the root of all evil.", author: "Donald Knuth"),
        Quote(text: "Make it work, make it right, make it fast.", author: "Kent Beck"),
        Quote(text: "Talk is cheap. Show me the code.", author: "Linus Torvalds"),
        Quote(text: "The only way to go fast is to go well.", author: "Robert C. Martin"),
        Quote(text: "Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away.", author: "Antoine de Saint-Exupéry"),
        Quote(text: "The first principle is that you must not fool yourself — and you are the easiest person to fool.", author: "Richard Feynman"),
        Quote(text: "If you don't work on important problems, it's not likely that you'll do important work.", author: "Richard Hamming, You and Your Research"),
        Quote(text: "Knowledge and productivity are like compound interest.", author: "Richard Hamming, You and Your Research"),
        Quote(text: "It always takes longer than you expect, even when you take into account Hofstadter's Law.", author: "Douglas Hofstadter, Gödel, Escher, Bach"),
        Quote(text: "Do. Or do not. There is no try.", author: "Yoda, The Empire Strikes Back"),
    ]

    static let rest: [Quote] = [
        Quote(text: "Almost everything will work again if you unplug it for a few minutes, including you.", author: "Anne Lamott"),
        Quote(text: "Rest is not idleness, and to lie sometimes on the grass under trees on a summer's day … is by no means a waste of time.", author: "John Lubbock, The Use of Life"),
        Quote(text: "Take rest; a field that has rested gives a bountiful crop.", author: "Ovid"),
        Quote(text: "The time to relax is when you don't have time for it.", author: "Sydney J. Harris"),
        Quote(text: "Stand up, stretch, look at something twenty feet away. Your next block will thank you.", author: "Pomo"),
        Quote(text: "Drink some water. Breathe out longer than you breathe in.", author: "Pomo"),
        Quote(text: "Step away from the screen. The answer often arrives when you stop chasing it.", author: "Pomo"),
    ]
}

/// Shuffle-bag per phase kind: no repeats until every quote has been shown; cursor persists across launches.
@MainActor
final class QuoteBag {
    private let defaults = UserDefaults.standard
    private var pools: [String: [Quote]] = [:]

    init() {
        pools["focus"] = QuoteLibrary.focus
        pools["rest"] = QuoteLibrary.rest
        if let override = Self.loadOverride() {
            if !override.focus.isEmpty { pools["focus"] = override.focus }
            if !override.rest.isEmpty { pools["rest"] = override.rest }
        }
    }

    func next(_ kind: String) -> Quote {
        let pool = pools[kind] ?? QuoteLibrary.focus
        var bag = defaults.array(forKey: "quoteBag.\(kind)") as? [Int] ?? []
        bag = bag.filter { $0 < pool.count }
        if bag.isEmpty { bag = Array(pool.indices).shuffled() }
        let idx = bag.removeFirst()
        defaults.set(bag, forKey: "quoteBag.\(kind)")
        return pool[idx]
    }

    private struct Override: Codable { var focus: [Quote] = []; var rest: [Quote] = [] }

    private static func loadOverride() -> Override? {
        let url = Paths.support.appendingPathComponent("quotes.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Override.self, from: data)
    }
}

enum Paths {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pomo", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
