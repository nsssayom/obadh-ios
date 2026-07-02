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

        if elapsed < mediumRepeatStart {
            return BackspaceRepeatStage(unit: .character, interval: 0.055)
        }
        if elapsed < fastRepeatStart {
            return BackspaceRepeatStage(unit: .character, interval: 0.044)
        }
        if elapsed < fastestRepeatStart {
            return BackspaceRepeatStage(unit: .character, interval: 0.035)
        }
        return BackspaceRepeatStage(unit: .character, interval: 0.028)
    }
}
