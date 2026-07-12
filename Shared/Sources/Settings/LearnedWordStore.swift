import Foundation

/// A personal lexicon that decides which words auto-insert must never "correct" — the
/// names, slang, and brand terms the built-in lexicon (`bn.fst`) doesn't know.
///
/// It does not flip a bit on first sight. Each word accumulates *evidence* that the user
/// means it, and is protected only once that evidence crosses a threshold — the way
/// personal-learning keyboards actually work:
///
/// - **Explicit keep** — the user tapped the quoted literal to reject a correction — is
///   the strongest signal ("this is my word"), and protects at once.
/// - **A plain commit** of an unknown word is weaker; a few are needed, so a one-off
///   typo never immunises itself.
/// - **Evidence decays** with time (frecency), so a word the user has stopped using
///   fades and stops being protected, and the store doesn't fill with stale entries.
///
/// The built-in lexicon is the primary gate, so this only ever matters for words outside
/// it. Bounded and persisted to the shared App Group so the keyboard and the app agree.
struct LearnedWordStore {
    /// How strongly an occurrence argues that the user means the word.
    enum Signal {
        /// The user chose their spelling over an offered correction. Deliberate.
        case explicitKeep
        /// The user committed the word in the normal course of typing.
        case commit

        var weight: Double {
            switch self {
            // Above the threshold with headroom, so one keep protects and stays
            // protected for weeks of disuse before decay pulls it under (~2 half-lives).
            case .explicitKeep: Self.protectThreshold * 4
            // Weak: three ordinary uses cross the line, one or two do not.
            case .commit: Self.protectThreshold * 0.4
            }
        }

        /// Evidence at or above this (after decay) means the word is protected.
        static let protectThreshold = 1.0
    }

    static let defaultLimit = 500
    /// Evidence halves after this long unused, so a months-dormant word fades out.
    private static let halfLife: TimeInterval = 30 * 24 * 60 * 60
    private static let key = "keyboard.learnedWords"

    private struct Entry {
        var score: Double
        var updatedAt: TimeInterval
    }

    private let defaults: UserDefaults
    private let limit: Int
    private let now: () -> Date

    init(
        defaults: UserDefaults = KeyboardPreferences.sharedDefaults,
        limit: Int = LearnedWordStore.defaultLimit,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.limit = max(1, limit)
        self.now = now
    }

    /// Whether the word has earned protection from auto-insert.
    func isProtected(_ word: String) -> Bool {
        let word = normalize(word)
        guard !word.isEmpty, let entry = load()[word] else { return false }
        return decayed(entry, at: now().timeIntervalSinceReferenceDate) >= Signal.protectThreshold
    }

    /// Add evidence that the user means this word. Idempotent-friendly: repeated calls
    /// accumulate, decayed to the moment of each call.
    func reinforce(_ word: String, signal: Signal) {
        let word = normalize(word)
        guard !word.isEmpty else { return }
        let timestamp = now().timeIntervalSinceReferenceDate

        var entries = load()
        let base = entries[word].map { decayed($0, at: timestamp) } ?? 0
        entries[word] = Entry(score: base + signal.weight, updatedAt: timestamp)

        if entries.count > limit, let weakest = leastEstablished(entries, at: timestamp) {
            entries.removeValue(forKey: weakest)
        }
        save(entries)
    }

    /// Forget everything (the app's "Clear Learned Words").
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Currently-protected words, strongest first — for a future management screen.
    func protectedWords() -> [String] {
        let timestamp = now().timeIntervalSinceReferenceDate
        return load()
            .filter { decayed($0.value, at: timestamp) >= Signal.protectThreshold }
            .sorted { decayed($0.value, at: timestamp) > decayed($1.value, at: timestamp) }
            .map(\.key)
    }

    // MARK: - Scoring

    private func decayed(_ entry: Entry, at timestamp: TimeInterval) -> Double {
        let elapsed = max(0, timestamp - entry.updatedAt)
        return entry.score * pow(2, -elapsed / Self.halfLife)
    }

    /// The entry with the least surviving evidence — evicted when the store is full.
    private func leastEstablished(_ entries: [String: Entry], at timestamp: TimeInterval) -> String? {
        entries.min { decayed($0.value, at: timestamp) < decayed($1.value, at: timestamp) }?.key
    }

    // MARK: - Persistence

    private func load() -> [String: Entry] {
        guard let raw = defaults.dictionary(forKey: Self.key) as? [String: [Double]] else {
            return [:]
        }
        return raw.compactMapValues { pair in
            pair.count == 2 ? Entry(score: pair[0], updatedAt: pair[1]) : nil
        }
    }

    private func save(_ entries: [String: Entry]) {
        defaults.set(entries.mapValues { [$0.score, $0.updatedAt] }, forKey: Self.key)
    }

    private func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
