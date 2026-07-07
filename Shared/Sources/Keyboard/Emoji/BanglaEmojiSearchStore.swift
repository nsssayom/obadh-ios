import Foundation

/// Bangla emoji-panel SEARCH over `emoji-bn-search.bin` (`OBEMOJIBN1`: token → up
/// to 16 ranked emoji). Loaded LAZILY — only when the panel is in Bangla search
/// mode — so the English default pays nothing. Supports exact + prefix + AND-of-
/// terms with Bangla-aware normalization (the English index folds diacritics,
/// which would destroy Bangla matras).
struct BanglaEmojiSearchStore {
    private let byToken: [String: [String]]
    private let allKeys: [String]

    var isEmpty: Bool { byToken.isEmpty }

    static let empty = BanglaEmojiSearchStore(byToken: [:], allKeys: [])

    private init(byToken: [String: [String]], allKeys: [String]) {
        self.byToken = byToken
        self.allKeys = allKeys
    }

    init(bundle: Bundle) {
        if let url = bundle.url(
            forResource: "emoji-bn-search",
            withExtension: "bin",
            subdirectory: "ObadhModels/emoji"
        ),
           let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
           let decoded = Self.decode(data) {
            self = BanglaEmojiSearchStore(byToken: decoded.0, allKeys: decoded.1)
        } else {
            self = .empty
        }
    }

    init?(data: Data) {
        guard let decoded = Self.decode(data) else { return nil }
        self = BanglaEmojiSearchStore(byToken: decoded.0, allKeys: decoded.1)
    }

    /// Emoji matching a Bangla query. Multiple terms are AND'd. Runs off the
    /// typing hot path (only while the emoji search field is active).
    func search(_ query: String, limit: Int) -> [String] {
        guard !byToken.isEmpty, limit > 0 else { return [] }
        let terms = Self.tokenize(query)
        guard !terms.isEmpty else { return [] }

        var perTerm = terms.map { emoji(forTerm: $0) }
        // Emoji-vocabulary autocorrect: if a term matched nothing exactly or by
        // prefix, fall back to an edit-distance match against the closed emoji
        // keyword vocabulary — aggressive is safe here because the only candidates
        // are emoji keywords. Runs ONLY on a miss (the common case pays nothing)
        // and only in this lazily-loaded search store (never on the typing path).
        for index in terms.indices where perTerm[index].isEmpty && terms[index].count >= 2 {
            perTerm[index] = fuzzyEmoji(forTerm: terms[index])
        }

        if perTerm.count == 1 {
            return Array(perTerm[0].prefix(limit))
        }
        // Multi-term: keep emoji present for every term, ordered by the first term.
        let laterSets = perTerm.dropFirst().map(Set.init)
        var result: [String] = []
        for emoji in perTerm[0] where laterSets.allSatisfy({ $0.contains(emoji) }) {
            result.append(emoji)
            if result.count == limit { break }
        }
        return result
    }

    /// Exact-token emoji first (strongest), then emoji from tokens that start with
    /// the term, deduped and order-preserving.
    private func emoji(forTerm term: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for emoji in byToken[term] ?? [] where seen.insert(emoji).inserted {
            result.append(emoji)
        }
        var scanned = 0
        for key in allKeys where key != term && key.hasPrefix(term) {
            for emoji in byToken[key] ?? [] where seen.insert(emoji).inserted {
                result.append(emoji)
            }
            scanned += 1
            if scanned >= 24 { break }
        }
        return result
    }

    /// Emoji from vocabulary tokens within a small grapheme edit-distance of the
    /// term (closest first). Bounded + length-pruned so it stays cheap even though
    /// it scans the vocabulary — and it only runs when exact+prefix found nothing.
    private func fuzzyEmoji(forTerm term: String) -> [String] {
        let termGraphemes = Array(term)
        let maxDistance = termGraphemes.count >= 6 ? 2 : 1
        var matches: [(key: String, distance: Int)] = []
        for key in allKeys {
            let keyGraphemes = Array(key)
            guard abs(keyGraphemes.count - termGraphemes.count) <= maxDistance else { continue }
            if let distance = Self.boundedEditDistance(termGraphemes, keyGraphemes, max: maxDistance) {
                matches.append((key, distance))
            }
        }
        matches.sort { $0.distance < $1.distance }

        var seen = Set<String>()
        var result: [String] = []
        for (key, _) in matches.prefix(6) {
            for emoji in byToken[key] ?? [] where seen.insert(emoji).inserted {
                result.append(emoji)
            }
        }
        return result
    }

    /// Grapheme-level Levenshtein with early exit; nil if it exceeds `max`.
    private static func boundedEditDistance(_ lhs: [Character], _ rhs: [Character], max maxDistance: Int) -> Int? {
        let n = lhs.count
        let m = rhs.count
        guard abs(n - m) <= maxDistance else { return nil }
        guard n > 0 else { return m <= maxDistance ? m : nil }
        guard m > 0 else { return n <= maxDistance ? n : nil }

        var previous = Array(0...m)
        var current = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            current[0] = i
            var rowMinimum = i
            for j in 1...m {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMinimum = Swift.min(rowMinimum, current[j])
            }
            guard rowMinimum <= maxDistance else { return nil }
            swap(&previous, &current)
        }
        let distance = previous[m]
        return distance <= maxDistance ? distance : nil
    }

    static func tokenize(_ query: String) -> [String] {
        BanglaEmojiSuggestionStore.normalize(query)
            .split { $0.isWhitespace || $0 == "," }
            .map(String.init)
            .filter { $0.count >= 1 }
    }

    // MARK: - Binary decoding (OBEMOJIBN1)

    private static func decode(_ data: Data) -> ([String: [String]], [String])? {
        data.withUnsafeBytes { bytes -> ([String: [String]], [String])? in
            let magic = Array("OBEMOJIBN1".utf8)
            guard bytes.count >= 30 else { return nil }
            for index in magic.indices where bytes[index] != magic[index] {
                return nil
            }
            let keyCount = Int(readUInt32(bytes, 14))
            let keyRecordsOffset = Int(readUInt32(bytes, 18))
            let stringBlobOffset = Int(readUInt32(bytes, 22))
            let stringBlobSize = Int(readUInt32(bytes, 26))
            guard
                keyCount >= 0,
                keyRecordsOffset + keyCount * 8 <= bytes.count,
                stringBlobOffset + stringBlobSize <= bytes.count
            else {
                return nil
            }

            func cString(at relativeOffset: Int) -> String {
                let start = stringBlobOffset + relativeOffset
                guard start >= 0, start < bytes.count else { return "" }
                var end = start
                while end < bytes.count, bytes[end] != 0 { end += 1 }
                return String(decoding: bytes[start..<end], as: UTF8.self)
            }

            var byToken: [String: [String]] = [:]
            byToken.reserveCapacity(keyCount)
            var allKeys: [String] = []
            allKeys.reserveCapacity(keyCount)
            for index in 0..<keyCount {
                let record = keyRecordsOffset + index * 8
                let key = cString(at: Int(readUInt32(bytes, record)))
                let value = cString(at: Int(readUInt32(bytes, record + 4)))
                let emojis = value.split(separator: "\u{1f}").map(String.init)
                byToken[key] = emojis
                allKeys.append(key)
            }
            return (byToken, allKeys)
        }
    }

    private static func readUInt32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
