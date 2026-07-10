import CoreGraphics
import Foundation

/// Geometry of the horizontally scrolling emoji grid.
///
/// Lives apart from `EmojiPanelView` so the arithmetic is testable: the view is a
/// UIKit type and cannot be reached from the test target.
enum EmojiGridMetrics {
    /// How many emoji occupy one screenful — `rowCount` × the columns that fit
    /// across the page.
    ///
    /// Only the leading inset is subtracted. The trailing inset pads the end of the
    /// *section*, not every screen: at scroll offset 0 the page runs from the
    /// leading inset to the collection view's right edge. Taking both off is enough
    /// to reject a column that genuinely fits — on a 430pt phone with a 44pt cell
    /// it costs the eighth column, and the recents row silently shrinks 32 → 28.
    static func pageCapacity(
        collectionWidth: CGFloat,
        leadingInset: CGFloat,
        columnSpacing: CGFloat,
        itemSide: CGFloat,
        rowCount: Int
    ) -> Int {
        guard collectionWidth > 0, itemSide > 0, rowCount > 0 else { return 0 }
        let pageWidth = max(1, collectionWidth - leadingInset)
        // n columns fit when n*side + (n-1)*spacing <= pageWidth.
        let columnCount = max(1, floor((pageWidth + columnSpacing) / (itemSide + columnSpacing)))
        return Int(columnCount) * rowCount
    }
}
