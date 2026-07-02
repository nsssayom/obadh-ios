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

    var accessibilityLabel: String {
        switch self {
        case .recents:
            "Recently Used"
        case .smileys:
            "Smileys and People"
        case .people:
            "People"
        case .animals:
            "Animals and Nature"
        case .food:
            "Food and Drink"
        case .activities:
            "Activities"
        case .travel:
            "Travel and Places"
        case .objects:
            "Objects"
        case .symbols:
            "Symbols"
        case .flags:
            "Flags"
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

    static func fromStorageCode(_ code: UInt8) -> Self? {
        switch code {
        case 1:
            .smileys
        case 2:
            .people
        case 3:
            .animals
        case 4:
            .food
        case 5:
            .activities
        case 6:
            .travel
        case 7:
            .objects
        case 8:
            .symbols
        case 9:
            .flags
        default:
            nil
        }
    }
}

struct EmojiDataStore {
    static let empty = EmojiDataStore(items: [])

    let items: [EmojiItem]
    private let displayItemsByCategory: [EmojiCategory: [EmojiItem]]
    private let itemsByEmoji: [String: EmojiItem]
    private let variantOptionsByEmoji: [String: [EmojiItem]]
    private let searchIndex: EmojiSearchIndex

    init(bundle: Bundle) {
        guard
            let url = bundle.url(
                forResource: "emoji",
                withExtension: "bin",
                subdirectory: "ObadhModels/emoji"
            ),
            let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
            let compiled = EmojiBinaryDecoder.decode(data)
        else {
            self.init(items: [])
            return
        }

        self.init(items: compiled.items, searchIndex: compiled.searchIndex)
    }

    init(binaryData data: Data) {
        guard let compiled = EmojiBinaryDecoder.decode(data) else {
            self.init(items: [])
            return
        }
        self.init(items: compiled.items, searchIndex: compiled.searchIndex)
    }

    init(items: [EmojiItem]) {
        self.init(items: items, searchIndex: EmojiSearchIndex(items: items))
    }

    private init(items: [EmojiItem], searchIndex: EmojiSearchIndex) {
        self.items = items
        displayItemsByCategory = Dictionary(
            grouping: items.filter { !Self.isSkinToneVariant($0.name) },
            by: \.category
        )
        itemsByEmoji = Dictionary(uniqueKeysWithValues: items.map { ($0.emoji, $0) })
        variantOptionsByEmoji = Self.makeVariantOptionsByEmoji(items: items)
        self.searchIndex = searchIndex
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

        return searchIndex.search(
            normalizedQuery: normalized,
            items: items,
            limit: limit
        )
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
                !character.isLetter && !character.isNumber
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

    fileprivate static func isSkinToneVariant(_ name: String) -> Bool {
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

private struct EmojiSearchIndex {
    private struct TokenPosting {
        let itemIndex: Int
        let weight: Int
    }

    private struct CandidateAccumulator {
        var bestScoreByTermIndex: [Int: Int] = [:]

        mutating func merge(termIndex: Int, termScore: Int) {
            if let existing = bestScoreByTermIndex[termIndex] {
                bestScoreByTermIndex[termIndex] = min(existing, termScore)
            } else {
                bestScoreByTermIndex[termIndex] = termScore
            }
        }

        var matchedTermCount: Int {
            bestScoreByTermIndex.count
        }

        var score: Int {
            bestScoreByTermIndex.values.reduce(0, +)
        }
    }

    private struct RankedCandidate {
        let item: EmojiItem
        let score: Int
        let index: Int

        func isRankedBefore(_ other: RankedCandidate) -> Bool {
            if score != other.score {
                return score < other.score
            }
            return index < other.index
        }
    }

    private let postingsByToken: [String: [TokenPosting]]
    private let sortedTokens: [String]

    init(items: [EmojiItem]) {
        var postingsByToken: [String: [TokenPosting]] = [:]

        for (index, item) in items.enumerated() {
            var bestWeightByToken: [String: Int] = [:]
            Self.add(tokens: EmojiDataStore.keywordTokens(from: item.normalizedName), weight: 0, into: &bestWeightByToken)
            Self.add(tokens: item.normalizedKeywords, weight: 2, into: &bestWeightByToken)
            Self.add(tokens: EmojiDataStore.keywordTokens(from: item.subgroup), weight: 5, into: &bestWeightByToken)

            for (token, weight) in bestWeightByToken {
                postingsByToken[token, default: []].append(TokenPosting(itemIndex: index, weight: weight))
            }
        }

        self.postingsByToken = postingsByToken
        sortedTokens = postingsByToken.keys.sorted()
    }

    init(compiledPostings: [(token: String, postings: [(itemIndex: Int, weight: Int)])]) {
        var postingsByToken: [String: [TokenPosting]] = [:]
        postingsByToken.reserveCapacity(compiledPostings.count)
        for entry in compiledPostings {
            postingsByToken[entry.token] = entry.postings.map {
                TokenPosting(itemIndex: $0.itemIndex, weight: $0.weight)
            }
        }
        self.postingsByToken = postingsByToken
        sortedTokens = postingsByToken.keys.sorted()
    }

    func search(normalizedQuery: String, items: [EmojiItem], limit: Int) -> [EmojiItem] {
        let queryTerms = Array(EmojiDataStore.keywordTokens(from: normalizedQuery).prefix(5))
        guard !queryTerms.isEmpty else { return [] }

        var accumulators: [Int: CandidateAccumulator] = [:]
        accumulators.reserveCapacity(limit * 8)

        for (termIndex, term) in queryTerms.enumerated() {
            let bestScores = bestTokenScores(for: term)
            for (itemIndex, score) in bestScores {
                var accumulator = accumulators[itemIndex] ?? CandidateAccumulator()
                accumulator.merge(termIndex: termIndex, termScore: score)
                accumulators[itemIndex] = accumulator
            }
        }

        let includesSkinToneQuery = normalizedQuery.contains("skin") || normalizedQuery.contains("tone")
        var candidates: [RankedCandidate] = []
        candidates.reserveCapacity(min(limit, accumulators.count))

        for (itemIndex, accumulator) in accumulators where accumulator.matchedTermCount == queryTerms.count {
            guard items.indices.contains(itemIndex) else { continue }
            let item = items[itemIndex]
            if EmojiDataStore.isSkinToneVariant(item.name) && !includesSkinToneQuery {
                continue
            }
            let score = phraseAdjustedScore(
                accumulator.score,
                item: item,
                normalizedQuery: normalizedQuery
            )
            insert(RankedCandidate(item: item, score: score, index: itemIndex), into: &candidates, limit: limit)
        }

        return candidates.map(\.item)
    }

    private static func add(tokens: [String], weight: Int, into bestWeightByToken: inout [String: Int]) {
        for token in tokens where token.count > 1 {
            if let existing = bestWeightByToken[token] {
                bestWeightByToken[token] = min(existing, weight)
            } else {
                bestWeightByToken[token] = weight
            }
        }
    }

    private func bestTokenScores(for term: String) -> [Int: Int] {
        var bestScores: [Int: Int] = [:]
        bestScores.reserveCapacity(24)

        addMatches(for: term, baseScore: 0, into: &bestScores)

        if term.count >= 2 {
            for token in prefixTokens(for: term) where token != term {
                addMatches(for: token, baseScore: 20, into: &bestScores)
            }
        }

        if term.count >= 3 {
            for token in sortedTokens where token.contains(term) && !token.hasPrefix(term) {
                addMatches(for: token, baseScore: 46, into: &bestScores)
            }

            let maxDistance = term.count >= 6 ? 2 : 1
            for token in sortedTokens where abs(token.count - term.count) <= maxDistance {
                guard let distance = Self.boundedEditDistance(term, token, maxDistance: maxDistance) else {
                    continue
                }
                addMatches(for: token, baseScore: 54 + distance * 10, into: &bestScores)
            }
        }

        return bestScores
    }

    private func addMatches(for token: String, baseScore: Int, into bestScores: inout [Int: Int]) {
        guard let postings = postingsByToken[token] else { return }
        for posting in postings {
            let score = baseScore + posting.weight
            if let existing = bestScores[posting.itemIndex] {
                bestScores[posting.itemIndex] = min(existing, score)
            } else {
                bestScores[posting.itemIndex] = score
            }
        }
    }

    private func prefixTokens(for prefix: String) -> ArraySlice<String> {
        var lowerBound = 0
        var upperBound = sortedTokens.count
        while lowerBound < upperBound {
            let mid = (lowerBound + upperBound) / 2
            if sortedTokens[mid] < prefix {
                lowerBound = mid + 1
            } else {
                upperBound = mid
            }
        }

        var end = lowerBound
        while end < sortedTokens.count, sortedTokens[end].hasPrefix(prefix) {
            end += 1
        }
        return sortedTokens[lowerBound..<end]
    }

    private func phraseAdjustedScore(_ score: Int, item: EmojiItem, normalizedQuery: String) -> Int {
        if item.normalizedName == normalizedQuery {
            return score - 80
        }
        if item.normalizedKeywords.contains(normalizedQuery) {
            return score - 70
        }
        if item.normalizedName.hasPrefix(normalizedQuery) {
            return score - 54
        }
        if item.searchText.hasPrefix(normalizedQuery) {
            return score - 42
        }
        if item.searchText.contains(normalizedQuery) {
            return score - 18
        }
        return score
    }

    private func insert(_ candidate: RankedCandidate, into candidates: inout [RankedCandidate], limit: Int) {
        var insertionIndex = candidates.endIndex
        for index in candidates.indices {
            if candidate.isRankedBefore(candidates[index]) {
                insertionIndex = index
                break
            }
        }

        if insertionIndex == candidates.endIndex {
            guard candidates.count < limit else { return }
            candidates.append(candidate)
            return
        }

        candidates.insert(candidate, at: insertionIndex)
        if candidates.count > limit {
            candidates.removeLast()
        }
    }

    private static func boundedEditDistance(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int? {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard abs(left.count - right.count) <= maxDistance else { return nil }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            var rowMinimum = current[0]

            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rightIndex])
            }

            guard rowMinimum <= maxDistance else { return nil }
            swap(&previous, &current)
        }

        let distance = previous[right.count]
        return distance <= maxDistance ? distance : nil
    }
}

private struct EmojiBinaryDecoder {
    private static let magic = Array("OBEMOJI1".utf8)
    private static let version: UInt32 = 1
    private static let headerSize = 44
    private static let itemRecordSize = 36
    private static let tokenRecordSize = 12
    private static let postingRecordSize = 8
    private static let keywordSeparator: Character = "\u{1f}"

    struct Result {
        let items: [EmojiItem]
        let searchIndex: EmojiSearchIndex
    }

    static func decode(_ data: Data) -> Result? {
        data.withUnsafeBytes { bytes in
            guard bytes.count >= headerSize else { return nil }
            for index in magic.indices where bytes[index] != magic[index] {
                return nil
            }
            guard readUInt32(bytes, at: 8) == version else { return nil }
            let itemCount = Int(readUInt32(bytes, at: 12))
            let tokenCount = Int(readUInt32(bytes, at: 16))
            let postingCount = Int(readUInt32(bytes, at: 20))
            let itemOffset = Int(readUInt32(bytes, at: 24))
            let tokenOffset = Int(readUInt32(bytes, at: 28))
            let postingOffset = Int(readUInt32(bytes, at: 32))
            let stringOffset = Int(readUInt32(bytes, at: 36))
            let stringSize = Int(readUInt32(bytes, at: 40))

            guard
                rangeIsValid(offset: itemOffset, count: itemCount, stride: itemRecordSize, total: bytes.count),
                rangeIsValid(offset: tokenOffset, count: tokenCount, stride: tokenRecordSize, total: bytes.count),
                rangeIsValid(offset: postingOffset, count: postingCount, stride: postingRecordSize, total: bytes.count),
                stringOffset >= 0,
                stringSize >= 0,
                stringOffset + stringSize <= bytes.count
            else {
                return nil
            }

            func string(at relativeOffset: UInt32) -> String? {
                let start = stringOffset + Int(relativeOffset)
                guard start >= stringOffset, start < stringOffset + stringSize else {
                    return nil
                }
                var end = start
                while end < stringOffset + stringSize, bytes[end] != 0 {
                    end += 1
                }
                guard end < stringOffset + stringSize else {
                    return nil
                }
                return String(decoding: bytes[start..<end], as: UTF8.self)
            }

            var items: [EmojiItem] = []
            items.reserveCapacity(itemCount)
            for itemIndex in 0..<itemCount {
                let offset = itemOffset + itemIndex * itemRecordSize
                guard let category = EmojiCategory.fromStorageCode(bytes[offset]) else {
                    return nil
                }
                let stringOffsets = (0..<8).map { fieldIndex in
                    readUInt32(bytes, at: offset + 4 + fieldIndex * 4)
                }
                guard
                    let emoji = string(at: stringOffsets[0]),
                    let group = string(at: stringOffsets[1]),
                    let subgroup = string(at: stringOffsets[2]),
                    let name = string(at: stringOffsets[3]),
                    let keywords = string(at: stringOffsets[4]),
                    let normalizedName = string(at: stringOffsets[5]),
                    let normalizedKeywordPayload = string(at: stringOffsets[6]),
                    let searchText = string(at: stringOffsets[7])
                else {
                    return nil
                }
                let normalizedKeywords = normalizedKeywordPayload
                    .split(separator: keywordSeparator)
                    .map(String.init)
                items.append(
                    EmojiItem(
                        emoji: emoji,
                        category: category,
                        group: group,
                        subgroup: subgroup,
                        name: name,
                        keywords: keywords,
                        normalizedName: normalizedName,
                        normalizedKeywords: normalizedKeywords,
                        searchText: searchText
                    )
                )
            }

            var compiledPostings: [(token: String, postings: [(itemIndex: Int, weight: Int)])] = []
            compiledPostings.reserveCapacity(tokenCount)
            for tokenIndex in 0..<tokenCount {
                let offset = tokenOffset + tokenIndex * tokenRecordSize
                guard let token = string(at: readUInt32(bytes, at: offset)) else {
                    return nil
                }
                let start = Int(readUInt32(bytes, at: offset + 4))
                let count = Int(readUInt32(bytes, at: offset + 8))
                guard start >= 0, count >= 0, start + count <= postingCount else {
                    return nil
                }

                var postings: [(itemIndex: Int, weight: Int)] = []
                postings.reserveCapacity(count)
                for postingIndex in start..<(start + count) {
                    let postingOffsetForIndex = postingOffset + postingIndex * postingRecordSize
                    let itemIndex = Int(readUInt32(bytes, at: postingOffsetForIndex))
                    let weight = Int(readUInt16(bytes, at: postingOffsetForIndex + 4))
                    guard itemIndex >= 0, itemIndex < itemCount else {
                        return nil
                    }
                    postings.append((itemIndex: itemIndex, weight: weight))
                }
                compiledPostings.append((token: token, postings: postings))
            }

            return Result(
                items: items,
                searchIndex: EmojiSearchIndex(compiledPostings: compiledPostings)
            )
        }
    }

    private static func rangeIsValid(offset: Int, count: Int, stride: Int, total: Int) -> Bool {
        guard offset >= 0, count >= 0, stride > 0 else { return false }
        guard count == 0 || offset <= total else { return false }
        return count <= (total - offset) / stride
    }

    private static func readUInt32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    private static func readUInt16(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt16 {
        UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }
}
