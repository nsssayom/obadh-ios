import Foundation
import XCTest
@testable import ObadhKeyboardCore

final class EmojiRecentStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "EmojiRecentStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordPromotesEmojiAndDeduplicates() {
        let store = EmojiRecentStore(defaults: defaults)

        store.record("😀")
        store.record("❤️")
        store.record("😀")

        XCTAssertEqual(store.load(), ["😀", "❤️"])
    }

    func testRecordPersistsAcrossStoreInstances() {
        EmojiRecentStore(defaults: defaults).record("🌸")

        XCTAssertEqual(EmojiRecentStore(defaults: defaults).load(), ["🌸"])
    }

    func testRecordKeepsBoundedRecentList() {
        let store = EmojiRecentStore(defaults: defaults)

        for index in 0..<70 {
            store.record("emoji-\(index)")
        }

        let values = store.load()
        XCTAssertEqual(values.count, 64)
        XCTAssertEqual(values.first, "emoji-69")
        XCTAssertEqual(values.last, "emoji-6")
    }
}
