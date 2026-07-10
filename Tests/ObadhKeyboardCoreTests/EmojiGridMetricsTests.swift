import CoreGraphics
import XCTest
@testable import ObadhKeyboardCore

final class EmojiGridMetricsTests: XCTestCase {
    private enum Layout {
        static let leadingInset: CGFloat = 14
        static let columnSpacing: CGFloat = 8
    }

    private func capacity(width: CGFloat, itemSide: CGFloat, rows: Int) -> Int {
        EmojiGridMetrics.pageCapacity(
            collectionWidth: width,
            leadingInset: Layout.leadingInset,
            columnSpacing: Layout.columnSpacing,
            itemSide: itemSide,
            rowCount: rows
        )
    }

    /// A column counts only when it fits whole: n*side + (n-1)*spacing <= page.
    private func columnsGenuinelyFit(_ count: Int, width: CGFloat, itemSide: CGFloat) -> Bool {
        let used = CGFloat(count) * itemSide + CGFloat(count - 1) * Layout.columnSpacing
        return used <= width - Layout.leadingInset
    }

    /// The regression: subtracting the trailing inset too dropped the eighth column
    /// on a 430pt phone with a 44pt cell, shrinking recents from 32 to 28.
    func testEighthColumnFitsOnAStandardPhone() {
        XCTAssertEqual(capacity(width: 430, itemSide: 44, rows: 4), 32)
        XCTAssertEqual(capacity(width: 430, itemSide: 45, rows: 4), 32)
    }

    /// Whatever the formula returns must actually fit, and one more must not.
    func testReportedColumnsAlwaysFitAndAreMaximal() {
        for width in stride(from: CGFloat(320), through: 1024, by: 1) {
            for side in stride(from: CGFloat(36), through: 46, by: 1) {
                let columns = capacity(width: width, itemSide: side, rows: 1)
                XCTAssertTrue(
                    columnsGenuinelyFit(columns, width: width, itemSide: side),
                    "\(columns) columns do not fit at width=\(width) side=\(side)"
                )
                if columns > 1 {
                    XCTAssertFalse(
                        columnsGenuinelyFit(columns + 1, width: width, itemSide: side),
                        "\(columns + 1) columns also fit at width=\(width) side=\(side); not maximal"
                    )
                }
            }
        }
    }

    /// A cell too wide for two columns still reports one, never zero.
    func testAlwaysReportsAtLeastOneColumn() {
        XCTAssertEqual(capacity(width: 60, itemSide: 46, rows: 1), 1)
    }

    func testCapacityScalesWithRows() {
        let oneRow = capacity(width: 430, itemSide: 44, rows: 1)
        XCTAssertEqual(capacity(width: 430, itemSide: 44, rows: 4), oneRow * 4)
    }

    /// A compact phone shows fewer than the store keeps, which is why the view
    /// clamps at all.
    func testCompactPhoneHoldsLessThanOnePageOfStoredRecents() {
        let compact = capacity(width: 375, itemSide: 40, rows: 4)
        XCTAssertLessThan(compact, EmojiRecentStore.defaultLimit)
    }

    func testDegenerateInputsReturnZero() {
        XCTAssertEqual(capacity(width: 0, itemSide: 40, rows: 4), 0)
        XCTAssertEqual(capacity(width: 430, itemSide: 0, rows: 4), 0)
        XCTAssertEqual(capacity(width: 430, itemSide: 40, rows: 0), 0)
    }
}
