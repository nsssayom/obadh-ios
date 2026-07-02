import Foundation

struct KeyboardKeyFrame: Equatable {
    let key: KeyboardKey
    let x: Double
    let width: Double
}

enum KeyboardLayoutGeometry {
    static func keyFrames(
        for row: KeyboardRow,
        availableWidth: Double,
        keySpacing: Double
    ) -> [KeyboardKeyFrame] {
        guard !row.keys.isEmpty, availableWidth > 0 else {
            return []
        }

        let leadingSpacer = row.leadingFlex > 0 ? row.leadingFlex : nil
        let trailingSpacer = row.trailingFlex > 0 ? row.trailingFlex : nil
        let keyWeights = row.keyWeights ?? row.keys.map(\.weight)
        let weights = [leadingSpacer].compactMap { $0 }
            + keyWeights
            + [trailingSpacer].compactMap { $0 }

        let gaps = spacingSequence(
            row: row,
            keyCount: row.keys.count,
            hasLeadingSpacer: leadingSpacer != nil,
            hasTrailingSpacer: trailingSpacer != nil,
            keySpacing: keySpacing
        )
        let totalGapWidth = gaps.reduce(0, +)
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0, availableWidth > totalGapWidth else {
            return []
        }

        let unitWidth = (availableWidth - totalGapWidth) / totalWeight
        var frames: [KeyboardKeyFrame] = []
        frames.reserveCapacity(row.keys.count)

        var x = 0.0
        var keyIndex = 0
        for itemIndex in weights.indices {
            let itemWidth = unitWidth * weights[itemIndex]
            let isLeadingSpacer = leadingSpacer != nil && itemIndex == 0
            let isTrailingSpacer = trailingSpacer != nil && itemIndex == weights.count - 1
            if !isLeadingSpacer, !isTrailingSpacer {
                frames.append(KeyboardKeyFrame(key: row.keys[keyIndex], x: x, width: itemWidth))
                keyIndex += 1
            }
            x += itemWidth
            if itemIndex < gaps.count {
                x += gaps[itemIndex]
            }
        }

        return frames
    }

    private static func spacingSequence(
        row: KeyboardRow,
        keyCount: Int,
        hasLeadingSpacer: Bool,
        hasTrailingSpacer: Bool,
        keySpacing: Double
    ) -> [Double] {
        let itemCount = keyCount + (hasLeadingSpacer ? 1 : 0) + (hasTrailingSpacer ? 1 : 0)
        guard itemCount > 1 else {
            return []
        }

        return (0..<(itemCount - 1)).map { itemIndex in
            if hasLeadingSpacer && itemIndex == 0 {
                return 0
            }
            let keyIndex = itemIndex - (hasLeadingSpacer ? 1 : 0)
            if hasTrailingSpacer && keyIndex == keyCount - 1 {
                return 0
            }
            if let customSpacing = row.customSpacingAfterKeyIndex[keyIndex] {
                return customSpacing * keySpacing / 6
            }
            return keySpacing
        }
    }
}
