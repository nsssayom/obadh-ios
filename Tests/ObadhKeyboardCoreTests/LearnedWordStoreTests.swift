import Foundation
import XCTest
@testable import ObadhKeyboardCore

final class LearnedWordStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock: TestClock!

    private final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        func advance(days: Double) { now = now.addingTimeInterval(days * 86_400) }
    }

    override func setUp() {
        super.setUp()
        suiteName = "LearnedWordStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        clock = TestClock()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        clock = nil
        super.tearDown()
    }

    private func makeStore(limit: Int = LearnedWordStore.defaultLimit) -> LearnedWordStore {
        LearnedWordStore(defaults: defaults, limit: limit, now: { [clock] in clock!.now })
    }

    /// An unseen word isn't protected.
    func testUnseenWordIsNotProtected() {
        XCTAssertFalse(makeStore().isProtected("টৌশিকুল"))
    }

    /// The strong signal — the user kept their spelling over a correction — protects at
    /// once, so they never fight the same name twice.
    func testExplicitKeepProtectsImmediately() {
        let store = makeStore()
        store.reinforce("টৌশিকুল", signal: .explicitKeep)
        XCTAssertTrue(store.isProtected("টৌশিকুল"))
    }

    /// A single ordinary commit is weak evidence — not enough on its own, so a one-off
    /// typo doesn't immunise itself.
    func testSingleCommitDoesNotProtect() {
        let store = makeStore()
        store.reinforce("ভুলবানান", signal: .commit)
        XCTAssertFalse(store.isProtected("ভুলবানান"))
    }

    /// Repeated ordinary use earns protection.
    func testRepeatedCommitsEarnProtection() {
        let store = makeStore()
        store.reinforce("নাটোর", signal: .commit)
        store.reinforce("নাটোর", signal: .commit)
        XCTAssertFalse(store.isProtected("নাটোর"))
        store.reinforce("নাটোর", signal: .commit)
        XCTAssertTrue(store.isProtected("নাটোর"))
    }

    /// Evidence decays: a protected word left unused long enough falls back below the
    /// threshold and stops being protected.
    func testProtectionFadesWhenUnused() {
        let store = makeStore()
        store.reinforce("পুরোনো", signal: .explicitKeep)
        XCTAssertTrue(store.isProtected("পুরোনো"))

        clock.advance(days: 120) // several half-lives
        XCTAssertFalse(store.isProtected("পুরোনো"))
    }

    /// Decayed evidence still accumulates: reinforcing a faded word tops it back up.
    func testReinforcingAFadedWordRestoresIt() {
        let store = makeStore()
        store.reinforce("শব্দ", signal: .explicitKeep)
        clock.advance(days: 120)
        XCTAssertFalse(store.isProtected("শব্দ"))

        store.reinforce("শব্দ", signal: .explicitKeep)
        XCTAssertTrue(store.isProtected("শব্দ"))
    }

    func testProtectionPersistsAcrossInstances() {
        makeStore().reinforce("মনে", signal: .explicitKeep)
        XCTAssertTrue(makeStore().isProtected("মনে"))
    }

    func testClearForgetsEverything() {
        let store = makeStore()
        store.reinforce("মুছে", signal: .explicitKeep)
        store.clear()
        XCTAssertFalse(makeStore().isProtected("মুছে"))
    }

    /// When full, the least-established word is evicted — a strongly-kept word survives a
    /// flood of one-off commits.
    func testEvictionDropsTheLeastEstablishedWord() {
        let store = makeStore(limit: 3)
        store.reinforce("রাখা", signal: .explicitKeep) // strong

        for index in 0..<5 {
            store.reinforce("once-\(index)", signal: .commit) // weak, distinct
            clock.advance(days: 0.01)
        }

        XCTAssertTrue(store.isProtected("রাখা"), "a kept word must survive weak-commit churn")
        XCTAssertLessThanOrEqual(store.protectedWords().count, 3)
    }

    /// Whitespace is normalised so " word " and "word" are the same entry.
    func testWhitespaceIsNormalised() {
        let store = makeStore()
        store.reinforce("  পদ্মা  ", signal: .explicitKeep)
        XCTAssertTrue(store.isProtected("পদ্মা"))
    }
}
