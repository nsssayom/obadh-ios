import Foundation

struct KeyboardTouchCellFrame: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var maxX: Double {
        x + width
    }
}

enum KeyboardTouchCellGeometry {
    static func cellFrames(
        for visualFrames: [KeyboardKeyFrame],
        availableWidth: Double,
        rowHeight: Double,
        topInset: Double,
        bottomInset: Double
    ) -> [KeyboardTouchCellFrame] {
        guard !visualFrames.isEmpty, availableWidth > 0, rowHeight > 0 else {
            return []
        }

        return visualFrames.indices.map { index in
            let minX: Double
            if index == visualFrames.startIndex {
                minX = 0
            } else {
                let previous = visualFrames[index - 1]
                let current = visualFrames[index]
                minX = midpoint(previous.x + previous.width, current.x)
            }

            let maxX: Double
            if index == visualFrames.index(before: visualFrames.endIndex) {
                maxX = availableWidth
            } else {
                let current = visualFrames[index]
                let next = visualFrames[index + 1]
                maxX = midpoint(current.x + current.width, next.x)
            }

            return KeyboardTouchCellFrame(
                x: minX,
                y: -topInset,
                width: max(0, maxX - minX),
                height: rowHeight + topInset + bottomInset
            )
        }
    }

    private static func midpoint(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs + rhs) / 2
    }
}
