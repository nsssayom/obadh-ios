import Foundation

/// Recently used emoji, newest first.
///
/// Order is pure most-recently-used: the emoji you just tapped is always first.
/// That is the expectation this row carries, and a usage-weighted order would
/// break it — a brand-new emoji would enter below your established favorites.
///
/// Weighting decides only what *leaves* the list once it is full. The entry with
/// the lowest time-decayed use count is dropped, not the oldest one, so an emoji
/// you reach for every week survives a burst of one-off novelty. Emoji use is
/// heavy-tailed: a handful account for nearly everything, and they are the ones
/// a plain oldest-out rule quietly loses.
///
/// The list holds a single screenful. Past the first page nobody scrolls — they
/// search — so the tail is dropped rather than retained.
struct EmojiRecentStore {
    private static let orderKey = "keyboard.emoji.recents"
    private static let scoresKey = "keyboard.emoji.recentScores"

    /// One page of the emoji grid on a standard phone layout (8 columns × 4 rows).
    /// `EmojiPanelView` clamps the rendered section to the page it actually has,
    /// which is smaller on compact devices.
    static let defaultLimit = 32

    /// A use is worth half as much after this long, so a two-week-old habit still
    /// outranks yesterday's novelty but a two-month-old one does not. Without decay
    /// the ranking ossifies: an emoji used heavily a year ago would outrank one you
    /// picked up this week, forever.
    private static let halfLife: TimeInterval = 14 * 24 * 60 * 60

    private struct Entry {
        var score: Double
        var updatedAt: TimeInterval
    }

    private let defaults: UserDefaults
    private let limit: Int
    private let now: () -> Date

    init(
        defaults: UserDefaults = KeyboardPreferences.sharedDefaults,
        limit: Int = EmojiRecentStore.defaultLimit,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.limit = max(1, limit)
        self.now = now
    }

    func load() -> [String] {
        defaults.stringArray(forKey: Self.orderKey) ?? []
    }

    func record(_ emoji: String) {
        let timestamp = now().timeIntervalSinceReferenceDate
        var order = load().filter { $0 != emoji }
        order.insert(emoji, at: 0)

        var scores = loadScores()
        scores[emoji] = Entry(
            score: decayedScore(scores[emoji], at: timestamp) + 1,
            updatedAt: timestamp
        )

        while order.count > limit, let index = leastValuableIndex(in: order, scores: scores, at: timestamp) {
            scores.removeValue(forKey: order.remove(at: index))
        }
        // Drop scores for anything no longer listed, including entries left behind
        // by an older build that stored a longer list.
        let listed = Set(order)
        scores = scores.filter { listed.contains($0.key) }

        defaults.set(order, forKey: Self.orderKey)
        defaults.set(scores.mapValues { [$0.score, $0.updatedAt] }, forKey: Self.scoresKey)
    }

    /// The entry to drop: lowest decayed score, oldest first on a tie. Index 0 was
    /// just used and is never a candidate — otherwise a fresh emoji arriving into a
    /// full list of established favorites would evict itself on the way in.
    private func leastValuableIndex(
        in order: [String],
        scores: [String: Entry],
        at timestamp: TimeInterval
    ) -> Int? {
        guard order.count > 1 else { return nil }
        var worst: (index: Int, score: Double)?
        for index in 1..<order.count {
            let score = decayedScore(scores[order[index]], at: timestamp)
            if let current = worst, score > current.score { continue }
            worst = (index, score)
        }
        return worst?.index
    }

    /// Entries with no score come from a build that only tracked order; treating
    /// them as zero makes the first eviction pass fall back to oldest-out.
    private func decayedScore(_ entry: Entry?, at timestamp: TimeInterval) -> Double {
        guard let entry else { return 0 }
        let elapsed = max(0, timestamp - entry.updatedAt)
        return entry.score * pow(2, -elapsed / Self.halfLife)
    }

    private func loadScores() -> [String: Entry] {
        guard let raw = defaults.object(forKey: Self.scoresKey) as? [String: [Double]] else {
            return [:]
        }
        return raw.compactMapValues { pair in
            pair.count == 2 ? Entry(score: pair[0], updatedAt: pair[1]) : nil
        }
    }
}
