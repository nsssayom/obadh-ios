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

    func testReportedLetterModeDeadZonesResolveToNearestKeys() throws {
        let rows = makeRows(for: .letters)
        let homeRow = rows[1]
        let lowerRow = rows[2]
        let aFrame = try XCTUnwrap(frame(for: .character("a"), in: homeRow))
        let lFrame = try XCTUnwrap(frame(for: .character("l"), in: homeRow))
        let shiftFrame = try XCTUnwrap(frame(for: .shift, in: lowerRow))
        let zFrame = try XCTUnwrap(frame(for: .character("z"), in: lowerRow))
        let mFrame = try XCTUnwrap(frame(for: .character("m"), in: lowerRow))
        let backspaceFrame = try XCTUnwrap(frame(for: .backspace, in: lowerRow))

        XCTAssertEqual(resolve(CGPoint(x: aFrame.minX / 2, y: aFrame.midY), rows: rows), .character("a"))
        XCTAssertEqual(
            resolve(CGPoint(x: lFrame.maxX + (keyboardWidth - lFrame.maxX) / 2, y: lFrame.midY), rows: rows),
            .character("l")
        )

        let shiftZGapMidX = (shiftFrame.maxX + zFrame.minX) / 2
        XCTAssertEqual(resolve(CGPoint(x: shiftZGapMidX - 0.5, y: zFrame.midY), rows: rows), .shift)
        XCTAssertEqual(resolve(CGPoint(x: shiftZGapMidX + 0.5, y: zFrame.midY), rows: rows), .character("z"))

        let mBackspaceGapMidX = (mFrame.maxX + backspaceFrame.minX) / 2
        XCTAssertEqual(resolve(CGPoint(x: mBackspaceGapMidX - 0.5, y: mFrame.midY), rows: rows), .character("m"))
        XCTAssertEqual(resolve(CGPoint(x: mBackspaceGapMidX + 0.5, y: mFrame.midY), rows: rows), .backspace)
    }

    func testEveryPointInEveryRowResolvesToSomeKey() {
        // Sweeps every integer x across every row (including all indents/gaps:
        // left-of-A, right-of-L, shift|z, m|backspace) and asserts the resolver
        // never returns nil — proving there are no interior dead zones.
        for mode in [KeyboardMode.letters, .numbers, .symbols] {
            let rows = makeRows(for: mode)
            let rowYs = rows.map { $0.first?.visualFrame.midY ?? 0 }
            for (rowIndex, y) in rowYs.enumerated() {
                var x: CGFloat = 0
                while x <= keyboardWidth {
                    let key = resolve(CGPoint(x: x, y: y), rows: rows)
                    XCTAssertNotNil(key, "nil at mode=\(mode) row=\(rowIndex) x=\(x) y=\(y)")
                    x += 1
                }
            }
        }
    }

    func testBelowBottomCommandRowResolvesToNearestCommandKey() throws {
        // The touch surface's frame extends below the visible command row to the
        // view edge; the resolver clamps taps that land there up to the last row
        // so space/return stay reachable instead of being dead.
        let rows = makeRows(for: .letters)
        let commandRow = rows[3]
        let space = try XCTUnwrap(frame(for: .space, in: commandRow))
        let returnKey = try XCTUnwrap(frame(for: .returnKey, in: commandRow))
        let modeSwitch = try XCTUnwrap(frame(for: .modeSwitch("123"), in: commandRow))
        let belowGrid = rowHeight * 4 + rowSpacing * 3 + 40

        XCTAssertEqual(resolve(CGPoint(x: modeSwitch.midX, y: belowGrid), rows: rows), .modeSwitch("123"))
        XCTAssertEqual(resolve(CGPoint(x: space.midX, y: belowGrid), rows: rows), .space)
        XCTAssertEqual(resolve(CGPoint(x: returnKey.midX, y: belowGrid), rows: rows), .returnKey)
    }

    func testAboveTopRowResolvesToNearestTopRowKey() throws {
        let rows = makeRows(for: .letters)
        let topRow = rows[0]
        let q = try XCTUnwrap(frame(for: .character("q"), in: topRow))
        let p = try XCTUnwrap(frame(for: .character("p"), in: topRow))
        let aboveGrid: CGFloat = -30

        XCTAssertEqual(resolve(CGPoint(x: q.midX, y: aboveGrid), rows: rows), .character("q"))
        XCTAssertEqual(resolve(CGPoint(x: p.midX, y: aboveGrid), rows: rows), .character("p"))
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
        let danda = try XCTUnwrap(frame(for: .symbol(.danda), in: lowerRow))
        let boundary = (modeSwitch.maxX + danda.minX) / 2

        XCTAssertEqual(resolve(CGPoint(x: boundary - 0.5, y: danda.midY), rows: rows), .modeSwitch("#+="))
        XCTAssertEqual(resolve(CGPoint(x: boundary + 0.5, y: danda.midY), rows: rows), .symbol(.danda))
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
