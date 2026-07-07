import Foundation

protocol BanglaTypingEngine {
    func transliterate(_ input: String) -> String
    func compositionSuggestions(for romanInput: String, limit: Int) -> [String]
    func autosuggestSuggestions(for context: String, limit: Int) -> [String]
}

struct KeyboardSuggestion: Equatable {
    let text: String
    let source: Source

    enum Source: Equatable {
        case deterministic
        case autocorrect
        case autosuggest
    }
}

final class KeyboardComposer {
    private let engine: BanglaTypingEngine
    private let emojiSuggester: BanglaEmojiSuggesting?
    private let compositionSuggestionLimit: Int
    private(set) var romanBuffer = ""
    private var compositionSuggestions: [KeyboardSuggestion] = []
    /// Up to 3 high-confidence emoji for the currently-composed word, shown in the
    /// bar's trailing region (which replaces the 3rd text candidate, native-style)
    /// — kept separate from the text candidates so the top two always survive.
    private var emojiSuggestions: [String] = []
    /// Bumped on every buffer change so stale async autocorrect results (fetched
    /// off the main thread) can be discarded when they arrive out of order.
    private(set) var generation = 0

    init(
        engine: BanglaTypingEngine,
        emojiSuggester: BanglaEmojiSuggesting? = nil,
        compositionSuggestionLimit: Int = 3
    ) {
        self.engine = engine
        self.emojiSuggester = emojiSuggester
        self.compositionSuggestionLimit = compositionSuggestionLimit
    }

    var hasActiveInput: Bool {
        !romanBuffer.isEmpty
    }

    /// Number of candidates the caller should request for the async autocorrect
    /// fetch (one extra so the deterministic entry never crowds out corrections).
    var autocorrectFetchLimit: Int {
        compositionSuggestionLimit + 1
    }

    var preview: String {
        compositionSuggestions.first?.text ?? ""
    }

    var activeSuggestions: [KeyboardSuggestion] {
        compositionSuggestions
    }

    /// Up to 3 emoji for the current word (best first), rendered by the bar in its
    /// trailing region. Empty when there's no confident match.
    var activeEmojis: [String] {
        emojiSuggestions
    }

    static func mergeSuggestions(
        primary: [KeyboardSuggestion],
        fallback: [KeyboardSuggestion],
        limit: Int
    ) -> [KeyboardSuggestion] {
        guard limit > 0 else { return [] }

        var merged: [KeyboardSuggestion] = []
        merged.reserveCapacity(limit)
        var seen = Set<String>()

        for suggestion in primary + fallback {
            guard !suggestion.text.isEmpty, seen.insert(suggestion.text).inserted else {
                continue
            }
            merged.append(suggestion)
            if merged.count == limit {
                break
            }
        }

        return merged
    }

    func append(_ scalar: String) {
        // `qq` (q tapped twice) is a mobile shortcut for Obadh's `^` chandrabindu
        // marker, which has no key on the letter layout. The second `q` rewrites
        // the pair to `^` so the engine renders ঁ.
        if scalar == "q", romanBuffer.hasSuffix("q") {
            romanBuffer.removeLast()
            romanBuffer.append("^")
        } else {
            romanBuffer.append(scalar)
        }
        refreshDeterministic()
    }

    func deleteBackward() -> Bool {
        guard hasActiveInput else { return false }
        romanBuffer.removeLast()
        refreshDeterministic()
        return true
    }

    func commitActiveInput() -> String? {
        guard hasActiveInput else { return nil }
        let committed = preview
        romanBuffer.removeAll(keepingCapacity: true)
        compositionSuggestions.removeAll(keepingCapacity: true)
        emojiSuggestions.removeAll(keepingCapacity: true)
        generation &+= 1
        return committed
    }

    func clear() {
        romanBuffer.removeAll(keepingCapacity: true)
        compositionSuggestions.removeAll(keepingCapacity: true)
        emojiSuggestions.removeAll(keepingCapacity: true)
        generation &+= 1
    }

    /// Fast, synchronous: computes only the deterministic transliteration for the
    /// inline marked-text preview. Autocorrect candidates (the expensive FST
    /// traversal) are merged in later via `mergeAutocorrectCandidates`, keeping
    /// them off the per-keystroke critical path.
    private func refreshDeterministic() {
        generation &+= 1
        guard hasActiveInput else {
            compositionSuggestions.removeAll(keepingCapacity: true)
            emojiSuggestions.removeAll(keepingCapacity: true)
            return
        }

        let deterministic = engine.transliterate(romanBuffer)
        if deterministic.isEmpty {
            compositionSuggestions.removeAll(keepingCapacity: true)
            emojiSuggestions.removeAll(keepingCapacity: true)
        } else {
            compositionSuggestions = [KeyboardSuggestion(text: deterministic, source: .deterministic)]
            // Exact-match emoji for the composed word — high confidence only, so
            // they appear just as a full known word is completed. Cheap binary
            // search, safe on the keystroke path.
            emojiSuggestions = emojiSuggester?.emojis(for: deterministic) ?? []
        }
    }

    /// Merges asynchronously-fetched autocorrect candidates behind the
    /// deterministic preview. Ignored if the buffer changed since the fetch was
    /// requested (generation mismatch).
    func mergeAutocorrectCandidates(_ candidates: [String], generation: Int) {
        guard generation == self.generation, hasActiveInput else { return }

        var merged: [KeyboardSuggestion] = []
        merged.reserveCapacity(compositionSuggestionLimit)
        var seen = Set<String>()

        if let deterministic = compositionSuggestions.first, deterministic.source == .deterministic {
            merged.append(deterministic)
            seen.insert(deterministic.text)
        }
        for text in candidates {
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            merged.append(KeyboardSuggestion(text: text, source: .autocorrect))
            if merged.count == compositionSuggestionLimit {
                break
            }
        }

        if !merged.isEmpty {
            compositionSuggestions = merged
        }
    }
}
