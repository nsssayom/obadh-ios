import XCTest
@testable import ObadhKeyboardCore

final class EmojiVariantPreferenceStoreTests: XCTestCase {
    func testRecordsPreferredVariantByBaseEmoji() {
        let defaults = makeDefaults()
        let store = EmojiVariantPreferenceStore(defaults: defaults)

        store.record(baseEmoji: "👋", selectedEmoji: "👋🏽")

        XCTAssertEqual(store.preferredEmoji(forBaseEmoji: "👋"), "👋🏽")
        XCTAssertEqual(store.load(), ["👋": "👋🏽"])
    }

    func testSelectingBaseEmojiClearsPreference() {
        let defaults = makeDefaults()
        let store = EmojiVariantPreferenceStore(defaults: defaults)

        store.record(baseEmoji: "👋", selectedEmoji: "👋🏽")
        store.record(baseEmoji: "👋", selectedEmoji: "👋")

        XCTAssertNil(store.preferredEmoji(forBaseEmoji: "👋"))
        XCTAssertTrue(store.load().isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "EmojiVariantPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
