import XCTest
@testable import ObadhKeyboardCore

final class KeyboardTouchCellGeometryTests: XCTestCase {
    private let phoneWidth = 440.0
    private let sideInset = 6.67
    private let keySpacing = 6.0
    private let rowHeight = 54.0

    func testTouchCellsTileHomeRowWithoutDeadZones() throws {
        let frames = KeyboardLayoutGeometry.keyFrames(
            for: KeyboardLayoutProvider.rows(for: .letters)[1],
            availableWidth: availableWidth,
            keySpacing: keySpacing
        )
        let shiftedFrames = shiftedIntoFullKeyboard(frames)
        let cells = touchCells(for: shiftedFrames, availableWidth: phoneWidth)

        XCTAssertEqual(cells.count, frames.count)
        assertContinuous(cells)
        XCTAssertEqual(cells[0].x, 0, accuracy: 0.001)
        XCTAssertEqual(cells.last?.maxX ?? -1, phoneWidth, accuracy: 0.001)

        let aIndex = try XCTUnwrap(keyIndex(.character("a"), in: shiftedFrames))
        let lIndex = try XCTUnwrap(keyIndex(.character("l"), in: shiftedFrames))
        XCTAssertEqual(cellIndex(containing: shiftedFrames[aIndex].x - 1, in: cells), aIndex)
        XCTAssertEqual(cellIndex(containing: shiftedFrames[lIndex].x + shiftedFrames[lIndex].width + 1, in: cells), lIndex)
        XCTAssertEqual(cellIndex(containing: 1, in: cells), aIndex)
        XCTAssertEqual(cellIndex(containing: phoneWidth - 1, in: cells), lIndex)
    }

    func testLowerRowLargeGapsSplitAtVisualMidpoints() throws {
        let frames = KeyboardLayoutGeometry.keyFrames(
            for: KeyboardLayoutProvider.rows(for: .letters)[2],
            availableWidth: availableWidth,
            keySpacing: keySpacing
        )
        let shiftedFrames = shiftedIntoFullKeyboard(frames)
        let cells = touchCells(for: shiftedFrames, availableWidth: phoneWidth)

        assertContinuous(cells)

        let shiftIndex = try XCTUnwrap(keyIndex(.shift, in: shiftedFrames))
        let zIndex = try XCTUnwrap(keyIndex(.character("z"), in: shiftedFrames))
        let shiftZBoundary = (shiftedFrames[shiftIndex].x + shiftedFrames[shiftIndex].width + shiftedFrames[zIndex].x) / 2
        XCTAssertEqual(cellIndex(containing: shiftZBoundary - 0.01, in: cells), shiftIndex)
        XCTAssertEqual(cellIndex(containing: shiftZBoundary + 0.01, in: cells), zIndex)

        let mIndex = try XCTUnwrap(keyIndex(.character("m"), in: shiftedFrames))
        let backspaceIndex = try XCTUnwrap(keyIndex(.backspace, in: shiftedFrames))
        let mBackspaceBoundary = (shiftedFrames[mIndex].x + shiftedFrames[mIndex].width + shiftedFrames[backspaceIndex].x) / 2
        XCTAssertEqual(cellIndex(containing: mBackspaceBoundary - 0.01, in: cells), mIndex)
        XCTAssertEqual(cellIndex(containing: mBackspaceBoundary + 0.01, in: cells), backspaceIndex)
        XCTAssertEqual(cellIndex(containing: 1, in: cells), shiftIndex)
        XCTAssertEqual(cellIndex(containing: phoneWidth - 1, in: cells), backspaceIndex)
    }

    func testVerticalInsetsCoverHalfInterRowGap() {
        let frames = KeyboardLayoutGeometry.keyFrames(
            for: KeyboardLayoutProvider.rows(for: .letters)[0],
            availableWidth: availableWidth,
            keySpacing: keySpacing
        )
        let cells = KeyboardTouchCellGeometry.cellFrames(
            for: frames,
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            topInset: 5,
            bottomInset: 5
        )

        XCTAssertEqual(cells.first?.y ?? 0, -5, accuracy: 0.001)
        XCTAssertEqual(cells.first?.height ?? 0, rowHeight + 10, accuracy: 0.001)
    }

    private var availableWidth: Double {
        phoneWidth - 2 * sideInset
    }

    private func touchCells(
        for frames: [KeyboardKeyFrame],
        availableWidth: Double? = nil
    ) -> [KeyboardTouchCellFrame] {
        KeyboardTouchCellGeometry.cellFrames(
            for: frames,
            availableWidth: availableWidth ?? self.availableWidth,
            rowHeight: rowHeight,
            topInset: 0,
            bottomInset: 0
        )
    }

    private func shiftedIntoFullKeyboard(_ frames: [KeyboardKeyFrame]) -> [KeyboardKeyFrame] {
        frames.map { frame in
            KeyboardKeyFrame(
                key: frame.key,
                x: sideInset + frame.x,
                width: frame.width
            )
        }
    }

    private func keyIndex(_ key: KeyboardKey, in frames: [KeyboardKeyFrame]) -> Int? {
        frames.firstIndex { $0.key == key }
    }

    private func cellIndex(containing x: Double, in cells: [KeyboardTouchCellFrame]) -> Int? {
        cells.firstIndex { cell in
            x >= cell.x && x < cell.maxX
        }
    }

    private func assertContinuous(_ cells: [KeyboardTouchCellFrame], file: StaticString = #filePath, line: UInt = #line) {
        guard let first = cells.first else {
            XCTFail("Expected at least one touch cell", file: file, line: line)
            return
        }

        XCTAssertEqual(first.x, 0, accuracy: 0.001, file: file, line: line)
        for index in cells.indices.dropFirst() {
            XCTAssertEqual(cells[index].x, cells[index - 1].maxX, accuracy: 0.001, file: file, line: line)
        }
    }
}
