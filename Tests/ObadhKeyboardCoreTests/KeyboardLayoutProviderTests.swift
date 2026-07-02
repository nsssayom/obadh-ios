import XCTest
@testable import ObadhKeyboardCore

final class KeyboardLayoutProviderTests: XCTestCase {
    private let phoneWidth = 440.0
    private let sideInset = 6.67
    private let keySpacing = 6.0

    func testAllModesKeepFourNativeRows() {
        for mode in [KeyboardMode.letters, .numbers, .symbols] {
            let rows = KeyboardLayoutProvider.rows(for: mode)

            XCTAssertEqual(rows.count, 4)
            XCTAssertEqual(rows[0].keys.count, 10)
            XCTAssertEqual(rows[1].keys.count, mode == .letters ? 9 : 10)
            XCTAssertEqual(rows[3].keys, [.modeSwitch(mode == .letters ? "123" : "ABC"), .emoji, .space, .returnKey])
        }
    }

    func testCommandRowsKeepNativeLikeBottomGeometryAcrossModes() {
        let letterBottom = KeyboardLayoutProvider.rows(for: .letters)[3]
        let numberBottom = KeyboardLayoutProvider.rows(for: .numbers)[3]
        let symbolBottom = KeyboardLayoutProvider.rows(for: .symbols)[3]

        XCTAssertEqual(numberBottom.keyWeights, letterBottom.keyWeights)
        XCTAssertEqual(symbolBottom.keyWeights, letterBottom.keyWeights)
        XCTAssertEqual(letterBottom.keyWeights, [48.0, 48.0, 210.67, 102.33])
    }

    func testNumberAndSymbolModesKeepNativeLikeTopRowGeometry() {
        for mode in [KeyboardMode.numbers, .symbols] {
            let rows = KeyboardLayoutProvider.rows(for: mode)

            for rowIndex in 0...1 {
                XCTAssertNil(rows[rowIndex].keyWeights)
                XCTAssertTrue(rows[rowIndex].customSpacingAfterKeyIndex.isEmpty)
                XCTAssertEqual(rows[rowIndex].leadingFlex, 0)
                XCTAssertEqual(rows[rowIndex].trailingFlex, 0)
                XCTAssertEqual(rows[rowIndex].keys.count, 10)
            }
        }
    }

    func testNumberAndSymbolModesKeepIdenticalCommandGeometry() {
        let numberRows = KeyboardLayoutProvider.rows(for: .numbers)
        let symbolRows = KeyboardLayoutProvider.rows(for: .symbols)

        XCTAssertEqual(numberRows[2].keyWeights, symbolRows[2].keyWeights)
        XCTAssertEqual(numberRows[2].customSpacingAfterKeyIndex, symbolRows[2].customSpacingAfterKeyIndex)
        XCTAssertEqual(numberRows[3].keyWeights, symbolRows[3].keyWeights)
    }

    func testLetterRowsUseMeasuredNativePhoneGeometry() throws {
        let rows = KeyboardLayoutProvider.rows(for: .letters)
        let homeRow = rows[1]
        let lowerRow = rows[2]

        XCTAssertEqual(homeRow.leadingFlex, 21.33 / 37.33, accuracy: 0.001)
        XCTAssertEqual(homeRow.trailingFlex, 21.33 / 37.33, accuracy: 0.001)
        XCTAssertEqual(lowerRow.customSpacingAfterKeyIndex[0], 14.67)
        XCTAssertEqual(lowerRow.customSpacingAfterKeyIndex[7], 14.67)

        let weights = try XCTUnwrap(lowerRow.keyWeights)
        XCTAssertEqual(weights[0], 50.33 / 37.33, accuracy: 0.001)
        XCTAssertEqual(weights[8], 50.33 / 37.33, accuracy: 0.001)
    }

    func testNumberAndSymbolPunctuationRowsReserveNativeSidePadding() throws {
        for mode in [KeyboardMode.numbers, .symbols] {
            let row = KeyboardLayoutProvider.rows(for: mode)[2]

            XCTAssertEqual(row.keys.count, 7)
            XCTAssertEqual(row.keyWeights?.count, row.keys.count)
            XCTAssertEqual(row.customSpacingAfterKeyIndex[0], 14.67)
            XCTAssertEqual(row.customSpacingAfterKeyIndex[5], 14.67)

            let weights = try XCTUnwrap(row.keyWeights)
            XCTAssertEqual(weights[0], 50.33 / 37.33, accuracy: 0.001)
            XCTAssertEqual(weights[1], 54.67 / 37.33, accuracy: 0.001)
            XCTAssertEqual(weights[5], 54.67 / 37.33, accuracy: 0.001)
            XCTAssertEqual(weights[6], 50.33 / 37.33, accuracy: 0.001)
        }
    }

    func testLetterRowsResolveToMeasuredNativeFrames() {
        let rows = KeyboardLayoutProvider.rows(for: .letters)
        let availableWidth = phoneWidth - 2 * sideInset

        let topRow = KeyboardLayoutGeometry.keyFrames(
            for: rows[0],
            availableWidth: availableWidth,
            keySpacing: keySpacing
        )
        XCTAssertEqual(topRow.count, 10)
        XCTAssertEqual(topRow[0].x + sideInset, 6.67, accuracy: 0.01)
        XCTAssertEqual(topRow[0].width, 37.27, accuracy: 0.01)
        XCTAssertEqual(topRow[1].x - topRow[0].x - topRow[0].width, 6.0, accuracy: 0.01)

        let homeRow = KeyboardLayoutGeometry.keyFrames(
            for: rows[1],
            availableWidth: availableWidth,
            keySpacing: keySpacing
        )
        XCTAssertEqual(homeRow.count, 9)
        XCTAssertEqual(homeRow[0].key, .character("a"))
        XCTAssertEqual(homeRow[0].x + sideInset, 28.0, accuracy: 0.02)
        XCTAssertEqual(homeRow[0].width, 37.33, accuracy: 0.02)
        XCTAssertEqual(homeRow[1].x - homeRow[0].x - homeRow[0].width, 6.0, accuracy: 0.01)

        let lowerRow = KeyboardLayoutGeometry.keyFrames(
            for: rows[2],
            availableWidth: availableWidth,
            keySpacing: keySpacing
        )
        XCTAssertEqual(lowerRow.count, 9)
        XCTAssertEqual(lowerRow[0].key, .shift)
        XCTAssertEqual(lowerRow[1].key, .character("z"))
        XCTAssertEqual(lowerRow[0].width, 50.25, accuracy: 0.03)
        XCTAssertEqual(lowerRow[1].width, 37.26, accuracy: 0.03)
        XCTAssertEqual(lowerRow[1].x - lowerRow[0].x - lowerRow[0].width, 14.67, accuracy: 0.01)
        XCTAssertEqual(lowerRow[8].x - lowerRow[7].x - lowerRow[7].width, 14.67, accuracy: 0.01)
    }

    func testCommandRowFramesStayStableAcrossModes() {
        let availableWidth = phoneWidth - 2 * sideInset
        for mode in [KeyboardMode.letters, .numbers, .symbols] {
            let row = KeyboardLayoutProvider.rows(for: mode)[3]
            let frames = KeyboardLayoutGeometry.keyFrames(
                for: row,
                availableWidth: availableWidth,
                keySpacing: keySpacing
            )

            XCTAssertEqual(frames.count, 4)
            XCTAssertEqual(frames[0].width, 47.96, accuracy: 0.03)
            XCTAssertEqual(frames[1].width, 47.96, accuracy: 0.03)
            XCTAssertEqual(frames[2].width, 210.50, accuracy: 0.05)
            XCTAssertEqual(frames[3].width, 102.25, accuracy: 0.05)
            XCTAssertEqual(frames[1].x - frames[0].x - frames[0].width, 6.0, accuracy: 0.01)
            XCTAssertEqual(frames[2].x - frames[1].x - frames[1].width, 6.0, accuracy: 0.01)
            XCTAssertEqual(frames[3].x - frames[2].x - frames[2].width, 6.0, accuracy: 0.01)
        }
    }
}
