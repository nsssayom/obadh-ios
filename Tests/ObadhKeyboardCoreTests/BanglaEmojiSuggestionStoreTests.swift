import Foundation
import XCTest
@testable import ObadhKeyboardCore

/// Round-trips the real generated `emoji-bn.bin` through the Swift decoder — so a
/// generator/format mismatch (offsets, sort order, separators, dedup) fails here
/// rather than silently on device.
final class BanglaEmojiSuggestionStoreTests: XCTestCase {
    private func loadStore() throws -> BanglaEmojiSuggestionStore {
        // .../Tests/ObadhKeyboardCoreTests/<thisFile> -> repo root is three up.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/ObadhModels/emoji/emoji-bn.bin")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(BanglaEmojiSuggestionStore(data: data))
    }

    func testCuratedWordsResolveToTheirEmoji() throws {
        let store = try loadStore()
        XCTAssertEqual(store.emojis(for: "ভালোবাসা").first, "❤️")
        XCTAssertEqual(store.emojis(for: "ট্রফি"), ["🏆"])
        XCTAssertTrue(store.emojis(for: "জন্মদিন").contains("🎂"))
        XCTAssertTrue(store.emojis(for: "ফুটবল").contains("⚽"))
    }

    func testReturnsAtMostThreeAndNoVisualDuplicates() throws {
        let store = try loadStore()
        for word in ["ধন্যবাদ", "ভালোবাসা", "বৃষ্টি", "আগুন", "পুরস্কার"] {
            let emojis = store.emojis(for: word)
            XCTAssertLessThanOrEqual(emojis.count, 3, "\(word) exceeded 3")
            // No skin-tone variants (base/neutral only).
            for emoji in emojis {
                for modifier in ["🏻", "🏼", "🏽", "🏾", "🏿"] {
                    XCTAssertFalse(emoji.contains(modifier), "\(word) surfaced a skin-tone variant")
                }
            }
            // No visual (VS16-insensitive) duplicates.
            let canonical = emojis.map { $0.replacingOccurrences(of: "\u{fe0f}", with: "") }
            XCTAssertEqual(Set(canonical).count, canonical.count, "\(word) has duplicate emoji")
        }
    }

    func testMissAndNormalizationBehaveExactly() throws {
        let store = try loadStore()
        XCTAssertTrue(store.emojis(for: "এইটাশব্দনা").isEmpty)
        XCTAssertTrue(store.emojis(for: "").isEmpty)
        // ZWNJ inside the word must not defeat the exact match.
        XCTAssertEqual(store.emojis(for: "ভালো\u{200c}বাসা").first, "❤️")
    }

    // MARK: - Bangla emoji SEARCH index

    private func loadSearchStore() throws -> BanglaEmojiSearchStore {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/ObadhModels/emoji/emoji-bn-search.bin")
        return try XCTUnwrap(BanglaEmojiSearchStore(data: try Data(contentsOf: url)))
    }

    func testBanglaSearchMatchesExactPrefixAndMisses() throws {
        let store = try loadSearchStore()
        XCTAssertFalse(store.search("হাসি", limit: 20).isEmpty, "exact token")
        XCTAssertFalse(store.search("ফুল", limit: 20).isEmpty, "exact token")
        XCTAssertFalse(store.search("হাস", limit: 20).isEmpty, "prefix (হাসি/হাসা/…)")
        XCTAssertTrue(store.search("এইটাশব্দনা", limit: 20).isEmpty, "miss")
        XCTAssertTrue(store.search("", limit: 20).isEmpty)
        // ZWNJ inside the query must not change results.
        XCTAssertEqual(store.search("হা\u{200c}সি", limit: 20), store.search("হাসি", limit: 20))
    }

    func testBanglaSearchFuzzyFallbackToleratesTypos() throws {
        let store = try loadSearchStore()
        let correct = store.search("হাসি", limit: 20)
        XCTAssertFalse(correct.isEmpty)
        // A close typo (শ for স) recovers via the vocabulary edit-distance fallback.
        XCTAssertFalse(store.search("হাশি", limit: 20).isEmpty, "fuzzy fallback should recover a close typo")
        // An exact hit must NOT change (fuzzy only runs on a miss).
        XCTAssertEqual(store.search("হাসি", limit: 20), correct)
        // Gibberish far from any token still returns nothing.
        XCTAssertTrue(store.search("এইটাখুবইঅদ্ভুতগিবারিশ", limit: 20).isEmpty)
    }
}
