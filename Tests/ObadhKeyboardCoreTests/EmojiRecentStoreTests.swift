import Foundation
import XCTest
@testable import ObadhKeyboardCore

final class EmojiRecentStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock: TestClock!

    /// Injected time source so decay is exercised without sleeping.
    private final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        func advance(days: Double) {
            now = now.addingTimeInterval(days * 24 * 60 * 60)
        }
    }

    override func setUp() {
        super.setUp()
        suiteName = "EmojiRecentStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        clock = TestClock()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        clock = nil
        super.tearDown()
    }

    private func makeStore(limit: Int = EmojiRecentStore.defaultLimit) -> EmojiRecentStore {
        EmojiRecentStore(defaults: defaults, limit: limit, now: { [clock] in clock!.now })
    }

    func testRecordPromotesEmojiAndDeduplicates() {
        let store = makeStore()

        store.record("😀")
        store.record("❤️")
        store.record("😀")

        XCTAssertEqual(store.load(), ["😀", "❤️"])
    }

    func testRecordPersistsAcrossStoreInstances() {
        makeStore().record("🌸")

        XCTAssertEqual(makeStore().load(), ["🌸"])
    }

    func testRecentListIsBoundedToOnePage() {
        let store = makeStore()

        for index in 0..<70 {
            store.record("emoji-\(index)")
        }

        let values = store.load()
        XCTAssertEqual(values.count, EmojiRecentStore.defaultLimit)
        XCTAssertEqual(values.first, "emoji-69")
    }

    /// The whole point of scoring: a habit outlives a flood of one-offs.
    func testRepeatedlyUsedEmojiSurvivesABurstOfNovelty() {
        let store = makeStore(limit: 3)

        for _ in 0..<5 {
            store.record("⭐️")
            clock.advance(days: 0.01)
        }
        // Five distinct one-offs, each seen once, into a three-slot list.
        for index in 0..<5 {
            store.record("novel-\(index)")
            clock.advance(days: 0.01)
        }

        let values = store.load()
        XCTAssertEqual(values.count, 3)
        XCTAssertTrue(values.contains("⭐️"), "a five-use emoji must outrank single-use novelty, got \(values)")
        XCTAssertEqual(values.first, "novel-4")
    }

    /// Plain oldest-out would have dropped ⭐️ here; frecency must not.
    func testOldestOutWouldEvictTheFavoriteButScoringDoesNot() {
        let store = makeStore(limit: 2)

        store.record("⭐️")
        store.record("⭐️")
        store.record("⭐️")
        clock.advance(days: 1)
        store.record("🆕")
        clock.advance(days: 1)
        store.record("🆖")

        let values = store.load()
        XCTAssertEqual(values, ["🆖", "⭐️"], "⭐️ is the oldest entry but the most used")
    }

    /// A just-tapped emoji is never the one evicted, even entering a full list of
    /// established favorites where it has the lowest score.
    func testJustUsedEmojiIsNeverEvicted() {
        let store = makeStore(limit: 2)

        for _ in 0..<4 { store.record("🅰️") }
        for _ in 0..<4 { store.record("🅱️") }
        store.record("🆕")

        let values = store.load()
        XCTAssertEqual(values.first, "🆕")
        XCTAssertEqual(values.count, 2)
    }

    /// Decay keeps the list from ossifying: a stale habit loses to a fresh one.
    func testScoreDecaysSoAStaleHabitLosesToARecentOne() {
        let store = makeStore(limit: 2)

        for _ in 0..<4 { store.record("🥀") }
        clock.advance(days: 120) // ~8.5 half-lives: 4.0 decays to well under 1

        store.record("🌱")
        store.record("🌱")
        clock.advance(days: 1)
        store.record("🆕") // forces one eviction

        XCTAssertEqual(store.load(), ["🆕", "🌱"], "the decayed 🥀 should lose to the fresh 🌱")
    }

    /// Entries written by a build that only tracked order carry no score; they must
    /// not crash and must degrade to oldest-out.
    func testMigratesFromAnUnscoredRecentList() {
        defaults.set(["a", "b", "c"], forKey: "keyboard.emoji.recents")
        let store = makeStore(limit: 2)

        store.record("d")

        XCTAssertEqual(store.load(), ["d", "a"], "unscored entries evict oldest-first")
    }
}
