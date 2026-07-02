import XCTest
@testable import ObadhKeyboardCore

final class BackspaceRepeatPolicyTests: XCTestCase {
    func testPolicyWaitsBeforeRepeating() {
        XCTAssertNil(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.2))
    }

    func testPolicyEscalatesFromCharactersToLargerChunks() {
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.5)?.unit, .character)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 1.4)?.unit, .word)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 3.0)?.unit, .sentence)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 4.5)?.unit, .availableContext)
    }

    func testWordPhaseIsSlowerThanCharacterPhase() {
        let character = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.5)
        let word = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 1.4)

        XCTAssertNotNil(character)
        XCTAssertNotNil(word)
        XCTAssertGreaterThan(word?.interval ?? 0, character?.interval ?? 1)
    }
}
