import Foundation

struct EmojiItem: Equatable {
    let emoji: String
    let category: EmojiCategory
    let group: String
    let subgroup: String
    let name: String
    let keywords: String
    let normalizedName: String
    let normalizedKeywords: [String]
    let searchText: String
}

enum EmojiCategory: String, CaseIterable {
    case recents
    case smileys
    case people
    case animals
    case food
    case activities
    case travel
    case objects
    case symbols
    case flags

    static let visibleCases: [Self] = [
        .recents,
        .smileys,
        .animals,
        .food,
        .activities,
        .travel,
        .objects,
        .symbols,
        .flags
    ]

    var symbolName: String {
        switch self {
        case .recents:
            "clock"
        case .smileys:
            "face.smiling"
        case .people:
            "person"
        case .animals:
            "pawprint"
        case .food:
            "fork.knife"
        case .activities:
            "soccerball"
        case .travel:
            "car"
        case .objects:
            "lightbulb"
        case .symbols:
            "heart"
        case .flags:
            "flag"
        }
    }

    static func fromUnicodeGroup(_ group: String) -> Self {
        switch group {
        case "Smileys & Emotion":
            .smileys
        case "People & Body":
            .people
        case "Animals & Nature":
            .animals
        case "Food & Drink":
            .food
        case "Activities":
            .activities
        case "Travel & Places":
            .travel
        case "Objects":
            .objects
        case "Symbols":
            .symbols
        case "Flags":
            .flags
        default:
            .symbols
        }
    }
}

struct EmojiDataStore {
    static let empty = EmojiDataStore(items: [])

    let items: [EmojiItem]
    private let displayItemsByCategory: [EmojiCategory: [EmojiItem]]
    private let itemsByEmoji: [String: EmojiItem]
    private let variantOptionsByEmoji: [String: [EmojiItem]]

    private struct SearchCandidate {
        let item: EmojiItem
        let score: Int
        let index: Int

        func isRankedBefore(_ other: SearchCandidate) -> Bool {
            if score != other.score {
                return score < other.score
            }
            return index < other.index
        }
    }

    init(bundle: Bundle) {
        guard
            let url = bundle.url(
                forResource: "emoji",
                withExtension: "tsv",
                subdirectory: "ObadhModels/emoji"
            ),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            self.init(items: [])
            return
        }

        var loadedItems: [EmojiItem] = []
        loadedItems.reserveCapacity(4_000)

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix("#") else { continue }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 5 else { continue }
            let group = String(columns[1])
            let name = String(columns[3])
            let keywords = String(columns[4])
            let item = EmojiItem(
                emoji: String(columns[0]),
                category: EmojiCategory.fromUnicodeGroup(group),
                group: group,
                subgroup: String(columns[2]),
                name: name,
                keywords: keywords,
                normalizedName: Self.normalize(name),
                normalizedKeywords: Self.keywordTokens(from: keywords),
                searchText: Self.normalize("\(name) \(keywords)")
            )
            loadedItems.append(item)
        }

        self.init(items: loadedItems)
    }

    init(items: [EmojiItem]) {
        self.items = items
        displayItemsByCategory = Dictionary(
            grouping: items.filter { !Self.isSkinToneVariant($0.name) },
            by: \.category
        )
        itemsByEmoji = Dictionary(uniqueKeysWithValues: items.map { ($0.emoji, $0) })
        variantOptionsByEmoji = Self.makeVariantOptionsByEmoji(items: items)
    }

    func items(in category: EmojiCategory) -> [EmojiItem] {
        if category == .smileys {
            return (displayItemsByCategory[.smileys] ?? []) + (displayItemsByCategory[.people] ?? [])
        }
        return displayItemsByCategory[category] ?? []
    }

    func items(for emojis: [String]) -> [EmojiItem] {
        emojis.compactMap { itemsByEmoji[$0] }
    }

    func item(for emoji: String) -> EmojiItem? {
        itemsByEmoji[emoji]
    }

    func variantOptions(for item: EmojiItem) -> [EmojiItem] {
        variantOptionsByEmoji[item.emoji] ?? []
    }

    func search(_ query: String, limit: Int) -> [EmojiItem] {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        var matches: [SearchCandidate] = []
        matches.reserveCapacity(min(limit, items.count))
        let includesSkinToneQuery = normalized.contains("skin") || normalized.contains("tone")
        for (index, item) in items.enumerated() {
            if Self.isSkinToneVariant(item.name) && !includesSkinToneQuery {
                continue
            }
            guard let score = searchScore(for: item, query: normalized) else {
                continue
            }
            insert(SearchCandidate(item: item, score: score, index: index), into: &matches, limit: limit)
        }

        return matches.map(\.item)
    }

    private func insert(_ candidate: SearchCandidate, into matches: inout [SearchCandidate], limit: Int) {
        var insertionIndex = matches.endIndex
        for index in matches.indices {
            if candidate.isRankedBefore(matches[index]) {
                insertionIndex = index
                break
            }
        }

        if insertionIndex == matches.endIndex {
            guard matches.count < limit else { return }
            matches.append(candidate)
            return
        }

        matches.insert(candidate, at: insertionIndex)
        if matches.count > limit {
            matches.removeLast()
        }
    }

    private func searchScore(for item: EmojiItem, query: String) -> Int? {
        if item.normalizedName == query {
            return 0
        }
        if item.normalizedKeywords.contains(query) {
            return 1
        }
        if item.normalizedName.hasPrefix(query) {
            return 2
        }
        if item.normalizedKeywords.contains(where: { $0.hasPrefix(query) }) {
            return 3
        }
        if item.normalizedName.contains(query) {
            return 4
        }
        if item.normalizedKeywords.contains(where: { $0.contains(query) }) {
            return 5
        }
        if item.searchText.contains(query) {
            return 6
        }
        return nil
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static func keywordTokens(from value: String) -> [String] {
        value
            .split { character in
                character == "," || character == ";" || character.isWhitespace
            }
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func makeVariantOptionsByEmoji(items: [EmojiItem]) -> [String: [EmojiItem]] {
        var baseItemsByName: [String: EmojiItem] = [:]
        for item in items where !isSkinToneVariant(item.name) {
            let key = normalize(item.name)
            if baseItemsByName[key] == nil {
                baseItemsByName[key] = item
            }
        }
        var variantGroups: [String: [EmojiItem]] = [:]
        for item in items {
            guard let baseKey = skinToneBaseKey(for: item.name) else { continue }
            variantGroups[baseKey, default: []].append(item)
        }

        var optionsByEmoji: [String: [EmojiItem]] = [:]
        for (baseKey, variants) in variantGroups {
            guard let baseItem = baseItemsByName[baseKey] else { continue }
            let sortedVariants = variants.sorted {
                if skinToneRank(for: $0.name) != skinToneRank(for: $1.name) {
                    return skinToneRank(for: $0.name) < skinToneRank(for: $1.name)
                }
                return $0.name < $1.name
            }
            let options = [baseItem] + sortedVariants
            guard options.count > 1 else { continue }
            for option in options {
                optionsByEmoji[option.emoji] = options
            }
        }
        return optionsByEmoji
    }

    private static func isSkinToneVariant(_ name: String) -> Bool {
        skinToneBaseKey(for: name) != nil
    }

    private static func skinToneBaseKey(for name: String) -> String? {
        guard let separator = name.range(of: ":") else { return nil }
        let suffix = normalize(String(name[separator.upperBound...]))
        guard suffix.hasSuffix("skin tone") else { return nil }
        return normalize(String(name[..<separator.lowerBound]))
    }

    private static func skinToneRank(for name: String) -> Int {
        let normalized = normalize(name)
        if normalized.contains("light skin tone"), !normalized.contains("medium-light") {
            return 1
        }
        if normalized.contains("medium-light skin tone") {
            return 2
        }
        if normalized.contains("medium skin tone"), !normalized.contains("medium-light"), !normalized.contains("medium-dark") {
            return 3
        }
        if normalized.contains("medium-dark skin tone") {
            return 4
        }
        if normalized.contains("dark skin tone"), !normalized.contains("medium-dark") {
            return 5
        }
        return 99
    }
}
