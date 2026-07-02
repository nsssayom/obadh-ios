import CoreGraphics

struct KeyboardTouchKeyRegion: Equatable {
    let key: KeyboardKey
    let visualFrame: CGRect
}

struct KeyboardTouchResolvedRegion: Equatable {
    let key: KeyboardKey
    let visualFrame: CGRect
}

enum KeyboardTouchResolver {
    static func resolve(
        point: CGPoint,
        rows: [[KeyboardTouchKeyRegion]],
        bounds: CGRect
    ) -> KeyboardTouchResolvedRegion? {
        guard !rows.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let nonEmptyRows = rows
            .map { row in row.filter { !$0.visualFrame.isEmpty } }
            .filter { !$0.isEmpty }
        guard !nonEmptyRows.isEmpty else {
            return nil
        }

        let sample = CGPoint(
            x: point.x.clamped(to: bounds.minX..<bounds.maxX),
            y: point.y.clamped(to: bounds.minY..<bounds.maxY)
        )

        let rowFrames = nonEmptyRows.map { unionFrame(for: $0) }
        let rowIndex = resolvedRowIndex(for: sample.y, rowFrames: rowFrames, bounds: bounds)
        let row = nonEmptyRows[rowIndex].sorted { lhs, rhs in
            lhs.visualFrame.minX < rhs.visualFrame.minX
        }

        guard let keyRegion = resolvedKeyRegion(for: sample.x, row: row, bounds: bounds) else {
            return nil
        }
        return KeyboardTouchResolvedRegion(
            key: keyRegion.key,
            visualFrame: keyRegion.visualFrame
        )
    }

    private static func resolvedRowIndex(
        for y: CGFloat,
        rowFrames: [CGRect],
        bounds: CGRect
    ) -> Int {
        for index in rowFrames.indices {
            let minY: CGFloat
            if index == rowFrames.startIndex {
                minY = bounds.minY
            } else {
                minY = midpoint(rowFrames[index - 1].maxY, rowFrames[index].minY)
            }

            let maxY: CGFloat
            if index == rowFrames.index(before: rowFrames.endIndex) {
                maxY = bounds.maxY
            } else {
                maxY = midpoint(rowFrames[index].maxY, rowFrames[index + 1].minY)
            }

            if y >= minY && y < maxY {
                return index
            }
        }

        return y < rowFrames[0].midY ? 0 : rowFrames.index(before: rowFrames.endIndex)
    }

    private static func resolvedKeyRegion(
        for x: CGFloat,
        row: [KeyboardTouchKeyRegion],
        bounds: CGRect
    ) -> KeyboardTouchKeyRegion? {
        for index in row.indices {
            let minX: CGFloat
            if index == row.startIndex {
                minX = bounds.minX
            } else {
                minX = midpoint(row[index - 1].visualFrame.maxX, row[index].visualFrame.minX)
            }

            let maxX: CGFloat
            if index == row.index(before: row.endIndex) {
                maxX = bounds.maxX
            } else {
                maxX = midpoint(row[index].visualFrame.maxX, row[index + 1].visualFrame.minX)
            }

            if x >= minX && x < maxX {
                return row[index]
            }
        }

        return x < row[0].visualFrame.midX ? row[0] : row.last
    }

    private static func unionFrame(for row: [KeyboardTouchKeyRegion]) -> CGRect {
        row.dropFirst().reduce(row[0].visualFrame) { partial, region in
            partial.union(region.visualFrame)
        }
    }

    private static func midpoint(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        (lhs + rhs) / 2
    }
}

private extension CGFloat {
    func clamped(to range: Range<CGFloat>) -> CGFloat {
        if self < range.lowerBound {
            return range.lowerBound
        }
        if self >= range.upperBound {
            return range.upperBound.nextDown
        }
        return self
    }
}
