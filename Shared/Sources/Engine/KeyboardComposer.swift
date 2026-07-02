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
    private let compositionSuggestionLimit: Int
    private(set) var romanBuffer = ""
    private var compositionSuggestions: [KeyboardSuggestion] = []

    init(engine: BanglaTypingEngine, compositionSuggestionLimit: Int = 3) {
        self.engine = engine
        self.compositionSuggestionLimit = compositionSuggestionLimit
    }

    var hasActiveInput: Bool {
        !romanBuffer.isEmpty
    }

    var preview: String {
        compositionSuggestions.first?.text ?? ""
    }

    var activeSuggestions: [KeyboardSuggestion] {
        compositionSuggestions
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

    func contextSuggestions(context: String, limit: Int) -> [KeyboardSuggestion] {
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return engine
            .autosuggestSuggestions(for: context, limit: limit)
            .filter { !$0.isEmpty }
            .map { KeyboardSuggestion(text: $0, source: .autosuggest) }
    }

    func append(_ scalar: String) {
        romanBuffer.append(scalar)
        refreshCompositionSuggestions()
    }

    func deleteBackward() -> Bool {
        guard hasActiveInput else { return false }
        romanBuffer.removeLast()
        refreshCompositionSuggestions()
        return true
    }

    func commitActiveInput() -> String? {
        guard hasActiveInput else { return nil }
        let committed = preview
        romanBuffer.removeAll(keepingCapacity: true)
        compositionSuggestions.removeAll(keepingCapacity: true)
        return committed
    }

    func clear() {
        romanBuffer.removeAll(keepingCapacity: true)
        compositionSuggestions.removeAll(keepingCapacity: true)
    }

    private func refreshCompositionSuggestions() {
        guard hasActiveInput else {
            compositionSuggestions.removeAll(keepingCapacity: true)
            return
        }

        let deterministic = engine.transliterate(romanBuffer)
        var suggestions: [KeyboardSuggestion] = []
        suggestions.reserveCapacity(compositionSuggestionLimit)
        var seen = Set<String>()

        if !deterministic.isEmpty {
            suggestions.append(KeyboardSuggestion(text: deterministic, source: .deterministic))
            seen.insert(deterministic)
        }

        for text in engine.compositionSuggestions(for: romanBuffer, limit: compositionSuggestionLimit + 1) {
            guard !text.isEmpty, !seen.contains(text) else {
                continue
            }
            suggestions.append(KeyboardSuggestion(text: text, source: .autocorrect))
            seen.insert(text)
            if suggestions.count == compositionSuggestionLimit {
                break
            }
        }

        compositionSuggestions = suggestions
    }
}
