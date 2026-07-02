import XCTest
@testable import ObadhKeyboardCore

final class BackspaceDeletionPlannerTests: XCTestCase {
    func testCharacterDeletionUsesSingleGraphemeCluster() {
        XCTAssertEqual(
            BackspaceDeletionPlanner.deleteCount(before: "দাঁড়িয়ে", unit: .character),
            1
        )
    }

    func testWordDeletionRemovesTrailingSeparatorAndWord() {
        XCTAssertEqual(
            BackspaceDeletionPlanner.deleteCount(before: "আমি ভালো আছি ", unit: .word),
            "আছি ".count
        )
    }

    func testWordDeletionStopsAtBanglaDanda() {
        XCTAssertEqual(
            BackspaceDeletionPlanner.deleteCount(before: "আমি ভালো। এখন", unit: .word),
            "এখন".count
        )
    }

    func testSentenceDeletionStopsAfterPreviousSentenceBoundary() {
        XCTAssertEqual(
            BackspaceDeletionPlanner.deleteCount(before: "আমি ভালো। এখন লিখছি", unit: .sentence),
            " এখন লিখছি".count
        )
    }

    func testAvailableContextDeletesVisibleContext() {
        XCTAssertEqual(
            BackspaceDeletionPlanner.deleteCount(before: "এক দুই তিন", unit: .availableContext),
            "এক দুই তিন".count
        )
    }
}
