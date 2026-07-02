import CoreGraphics
import XCTest
@testable import ObadhKeyboardCore

final class KeyboardTouchResolverTests: XCTestCase {
    private let keyboardWidth: CGFloat = 440
    private let sideInset: CGFloat = 6.67
    private let keySpacing: CGFloat = 6
    private let rowHeight: CGFloat = 54
    private let rowSpacing: CGFloat = 6

    func testHomeRowIndentResolvesToNearestHomeRowKeys() throws {
        let rows = makeRows(for: .letters)
        let homeRow = rows[1]
        let aFrame = try XCTUnwrap(frame(for: .character("a"), in: homeRow))
        let lFrame = try XCTUnwrap(frame(for: .character("l"), in: homeRow))

        XCTAssertEqual(resolve(CGPoint(x: 1, y: aFrame.midY), rows: rows), .character("a"))
        XCTAssertEqual(resolve(CGPoint(x: aFrame.minX - 8, y: aFrame.midY), rows: rows), .character("a"))
        XCTAssertEqual(resolve(CGPoint(x: keyboardWidth - 1, y: lFrame.midY), rows: rows), .character("l"))
        XCTAssertEqual(resolve(CGPoint(x: lFrame.maxX + 8, y: lFrame.midY), rows: rows), .character("l"))
    }

    func testLowerRowLargeGapsSplitAtNearestKeyBoundary() throws {
        let rows = makeRows(for: .letters)
        let lowerRow = rows[2]
        let shift = try XCTUnwrap(frame(for: .shift, in: lowerRow))
        let z = try XCTUnwrap(frame(for: .character("z"), in: lowerRow))
        let m = try XCTUnwrap(frame(for: .character("m"), in: lowerRow))
        let backspace = try XCTUnwrap(frame(for: .backspace, in: lowerRow))

        let shiftZBoundary = (shift.maxX + z.minX) / 2
        XCTAssertEqual(resolve(CGPoint(x: shiftZBoundary - 0.5, y: z.midY), rows: rows), .shift)
        XCTAssertEqual(resolve(CGPoint(x: shiftZBoundary + 0.5, y: z.midY), rows: rows), .character("z"))

        let mBackspaceBoundary = (m.maxX + backspace.minX) / 2
        XCTAssertEqual(resolve(CGPoint(x: mBackspaceBoundary - 0.5, y: m.midY), rows: rows), .character("m"))
        XCTAssertEqual(resolve(CGPoint(x: mBackspaceBoundary + 0.5, y: m.midY), rows: rows), .backspace)
    }

    func testVerticalRowGapsSplitAtNearestRowBoundary() throws {
        let rows = makeRows(for: .letters)
        let q = try XCTUnwrap(frame(for: .character("q"), in: rows[0]))
        let a = try XCTUnwrap(frame(for: .character("a"), in: rows[1]))
        let boundary = (q.maxY + a.minY) / 2

        XCTAssertEqual(resolve(CGPoint(x: q.midX, y: boundary - 0.5), rows: rows), .character("q"))
        XCTAssertEqual(resolve(CGPoint(x: q.midX, y: boundary + 0.5), rows: rows), .character("a"))
    }

    func testPunctuationModeUsesSameContinuousSurface() throws {
        let rows = makeRows(for: .numbers)
        let lowerRow = rows[2]
        let modeSwitch = try XCTUnwrap(frame(for: .modeSwitch("#+="), in: lowerRow))
        let period = try XCTUnwrap(frame(for: .symbol(.sentencePeriod), in: lowerRow))
        let boundary = (modeSwitch.maxX + period.minX) / 2

        XCTAssertEqual(resolve(CGPoint(x: boundary - 0.5, y: period.midY), rows: rows), .modeSwitch("#+="))
        XCTAssertEqual(resolve(CGPoint(x: boundary + 0.5, y: period.midY), rows: rows), .symbol(.sentencePeriod))
    }

    private func makeRows(for mode: KeyboardMode) -> [[KeyboardTouchKeyRegion]] {
        KeyboardLayoutProvider.rows(for: mode).enumerated().map { rowIndex, row in
            let y = CGFloat(rowIndex) * (rowHeight + rowSpacing)
            return KeyboardLayoutGeometry.keyFrames(
                for: row,
                availableWidth: Double(keyboardWidth - sideInset * 2),
                keySpacing: Double(keySpacing)
            ).map { frame in
                KeyboardTouchKeyRegion(
                    key: frame.key,
                    visualFrame: CGRect(
                        x: sideInset + CGFloat(frame.x),
                        y: y,
                        width: CGFloat(frame.width),
                        height: rowHeight
                    )
                )
            }
        }
    }

    private func resolve(
        _ point: CGPoint,
        rows: [[KeyboardTouchKeyRegion]]
    ) -> KeyboardKey? {
        KeyboardTouchResolver.resolve(
            point: point,
            rows: rows,
            bounds: CGRect(
                x: 0,
                y: 0,
                width: keyboardWidth,
                height: rowHeight * 4 + rowSpacing * 3
            )
        )?.key
    }

    private func frame(
        for key: KeyboardKey,
        in row: [KeyboardTouchKeyRegion]
    ) -> CGRect? {
        row.first { $0.key == key }?.visualFrame
    }
}
