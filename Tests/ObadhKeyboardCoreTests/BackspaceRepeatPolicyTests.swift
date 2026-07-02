import XCTest
@testable import ObadhKeyboardCore

final class BackspaceRepeatPolicyTests: XCTestCase {
    func testPolicyWaitsBeforeRepeating() {
        XCTAssertNil(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.2))
    }

    func testPolicyAlwaysRepeatsCharacterDeletion() {
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.5)?.unit, .character)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 1.4)?.unit, .character)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 3.0)?.unit, .character)
        XCTAssertEqual(BackspaceRepeatPolicy.nativeLike.stage(elapsed: 4.5)?.unit, .character)
    }

    func testRepeatIntervalGetsFasterDuringLongHold() {
        let initial = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 0.5)
        let medium = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 1.4)
        let fast = BackspaceRepeatPolicy.nativeLike.stage(elapsed: 3.0)

        XCTAssertNotNil(initial)
        XCTAssertNotNil(medium)
        XCTAssertNotNil(fast)
        XCTAssertLessThan(medium?.interval ?? 1, initial?.interval ?? 0)
        XCTAssertLessThan(fast?.interval ?? 1, medium?.interval ?? 0)
    }
}
