import XCTest
@testable import ObadhKeyboardCore

final class BackspaceRepeatPolicyTests: XCTestCase {
    func testPolicyWaitsBeforeRepeating() {
        XCTAssertNil(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.2))
    }

    /// A short hold stays character-by-character, so small corrections are precise.
    func testShortHoldDeletesCharacters() {
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.5)?.unit, .character)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 1.4)?.unit, .character)
    }

    /// A sustained hold graduates to whole-word deletion, native-style.
    func testSustainedHoldDeletesWords() {
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 3.0)?.unit, .word)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 4.5)?.unit, .word)
    }

    /// Within the character phase, the interval tightens.
    func testCharacterRepeatAcceleratesBeforeEscalating() {
        let initial = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.5)
        let medium = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 1.4)

        XCTAssertEqual(initial?.unit, .character)
        XCTAssertEqual(medium?.unit, .character)
        XCTAssertLessThan(medium?.interval ?? 1, initial?.interval ?? 0)
    }
}
