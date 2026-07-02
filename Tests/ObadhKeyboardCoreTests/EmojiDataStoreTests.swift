import Foundation
import XCTest
@testable import ObadhKeyboardCore

final class EmojiDataStoreTests: XCTestCase {
    func testCompiledEmojiBinaryLoadsAndSearches() throws {
        let data = try Data(contentsOf: repositoryRoot()
            .appendingPathComponent("Resources/ObadhModels/emoji/emoji.bin"))
        let store = EmojiDataStore(binaryData: data)

        XCTAssertGreaterThan(store.items.count, 3_500)
        XCTAssertEqual(store.search("red heart", limit: 5).first?.emoji, "❤️")
        XCTAssertFalse(store.search("smil", limit: 10).isEmpty)
        XCTAssertTrue(store.search("grinning", limit: 10).contains { $0.emoji == "😀" })
    }

    func testSearchIgnoresEmptyQueries() {
        let store = EmojiDataStore(items: [
            emoji("❤️", name: "red heart", keywords: "heart,love")
        ])

        XCTAssertEqual(store.search("", limit: 10), [])
        XCTAssertEqual(store.search("   ", limit: 10), [])
    }

    func testSearchMatchesNameAndKeywordsCaseInsensitively() {
        let heart = emoji("❤️", name: "red heart", keywords: "heart,love")
        let grin = emoji("😀", name: "grinning face", keywords: "smile,happy")
        let store = EmojiDataStore(items: [heart, grin])

        XCTAssertEqual(store.search("HEART", limit: 10), [heart])
        XCTAssertEqual(store.search("smile", limit: 10), [grin])
    }

    func testSearchHonorsLimit() {
        let items = [
            emoji("❤️", name: "red heart", keywords: "heart,love"),
            emoji("💙", name: "blue heart", keywords: "heart,love")
        ]
        let store = EmojiDataStore(items: items)

        XCTAssertEqual(store.search("heart", limit: 1), [items[0]])
    }

    func testSearchRanksExactAndPrefixMatchesAheadOfLooseSubstringMatches() {
        let looseSubstring = emoji("🫙", name: "jar", keywords: "heartland")
        let namePrefix = emoji("❤️", name: "heart", keywords: "love")
        let keywordExact = emoji("💙", name: "blue heart", keywords: "heart,love")
        let store = EmojiDataStore(items: [looseSubstring, namePrefix, keywordExact])

        XCTAssertEqual(store.search("heart", limit: 10), [namePrefix, keywordExact, looseSubstring])
    }

    func testBoundedSearchKeepsLateHigherRankedMatches() {
        let earlyLoose = emoji("🫙", name: "jar", keywords: "heartland")
        let secondLoose = emoji("🪵", name: "log", keywords: "heartwood")
        let lateExact = emoji("❤️", name: "heart", keywords: "love")
        let store = EmojiDataStore(items: [earlyLoose, secondLoose, lateExact])

        XCTAssertEqual(store.search("heart", limit: 2), [lateExact, earlyLoose])
    }

    func testSmileysCategoryIncludesPeopleAndBodyItemsForNativeCategoryGrouping() {
        let smiley = emoji("😀", category: .smileys, name: "grinning face", keywords: "smile")
        let person = emoji("👋", category: .people, name: "waving hand", keywords: "wave")
        let animal = emoji("🐶", category: .animals, name: "dog face", keywords: "pet")
        let store = EmojiDataStore(items: [smiley, person, animal])

        XCTAssertEqual(store.items(in: .smileys), [smiley, person])
        XCTAssertEqual(store.items(in: .animals), [animal])
        XCTAssertFalse(EmojiCategory.visibleCases.contains(.people))
    }

    func testSkinToneVariantsAreGroupedBehindBaseEmoji() {
        let base = emoji("👋", category: .people, name: "waving hand", keywords: "wave")
        let medium = emoji("👋🏽", category: .people, name: "waving hand: medium skin tone", keywords: "waving hand: medium skin tone")
        let light = emoji("👋🏻", category: .people, name: "waving hand: light skin tone", keywords: "waving hand: light skin tone")
        let store = EmojiDataStore(items: [base, medium, light])

        XCTAssertEqual(store.items(in: .smileys), [base])
        XCTAssertEqual(store.variantOptions(for: base), [base, light, medium])
        XCTAssertEqual(store.variantOptions(for: medium), [base, light, medium])
    }

    func testEmojiLookupResolvesBaseAndVariantItems() {
        let base = emoji("👋", category: .people, name: "waving hand", keywords: "wave")
        let variant = emoji("👋🏽", category: .people, name: "waving hand: medium skin tone", keywords: "waving hand: medium skin tone")
        let store = EmojiDataStore(items: [base, variant])

        XCTAssertEqual(store.item(for: "👋"), base)
        XCTAssertEqual(store.item(for: "👋🏽"), variant)
        XCTAssertNil(store.item(for: "missing"))
    }

    func testSearchHidesSkinToneVariantsUnlessQueryMentionsSkinTone() {
        let base = emoji("👋", category: .people, name: "waving hand", keywords: "wave")
        let variant = emoji("👋🏿", category: .people, name: "waving hand: dark skin tone", keywords: "waving hand: dark skin tone")
        let store = EmojiDataStore(items: [base, variant])

        XCTAssertEqual(store.search("waving", limit: 10), [base])
        XCTAssertEqual(store.search("dark skin", limit: 10), [variant])
    }

    private func emoji(
        _ value: String,
        category: EmojiCategory = .smileys,
        name: String,
        keywords: String
    ) -> EmojiItem {
        let normalizedName = EmojiDataStore.normalize(name)
        let normalizedKeywords = EmojiDataStore.keywordTokens(from: keywords)
        return EmojiItem(
            emoji: value,
            category: category,
            group: groupName(for: category),
            subgroup: "fixture",
            name: name,
            keywords: keywords,
            normalizedName: normalizedName,
            normalizedKeywords: normalizedKeywords,
            searchText: EmojiDataStore.normalize("\(name) \(keywords)")
        )
    }

    private func groupName(for category: EmojiCategory) -> String {
        switch category {
        case .smileys:
            return "Smileys & Emotion"
        case .people:
            return "People & Body"
        case .animals:
            return "Animals & Nature"
        case .food:
            return "Food & Drink"
        case .activities:
            return "Activities"
        case .travel:
            return "Travel & Places"
        case .objects:
            return "Objects"
        case .symbols:
            return "Symbols"
        case .flags:
            return "Flags"
        case .recents:
            return "Recently Used"
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
