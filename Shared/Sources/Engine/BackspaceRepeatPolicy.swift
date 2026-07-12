import Foundation

struct BackspaceRepeatStage: Equatable {
    let unit: BackspaceDeletionUnit
    let interval: TimeInterval
}

struct BackspaceRepeatPolicy {
    static let nativeLike = Self(
        initialDelay: 0.38,
        mediumRepeatStart: 1.2,
        fastRepeatStart: 2.8,
        fastestRepeatStart: 4.2
    )

    let initialDelay: TimeInterval
    let mediumRepeatStart: TimeInterval
    let fastRepeatStart: TimeInterval
    let fastestRepeatStart: TimeInterval

    func stage(elapsed: TimeInterval) -> BackspaceRepeatStage? {
        guard elapsed >= initialDelay else { return nil }

        // A brief hold accelerates character-by-character, so short corrections stay
        // precise. A sustained hold graduates to whole-word deletion, the way the
        // system keyboard does, so clearing a phrase doesn't take forever.
        if elapsed < mediumRepeatStart {
            return BackspaceRepeatStage(unit: .character, interval: 0.055)
        }
        if elapsed < fastRepeatStart {
            return BackspaceRepeatStage(unit: .character, interval: 0.044)
        }
        if elapsed < fastestRepeatStart {
            return BackspaceRepeatStage(unit: .word, interval: 0.12)
        }
        return BackspaceRepeatStage(unit: .word, interval: 0.09)
    }
}
