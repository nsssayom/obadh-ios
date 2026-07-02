import Foundation

struct BackspaceRepeatStage: Equatable {
    let unit: BackspaceDeletionUnit
    let interval: TimeInterval
}

struct BackspaceRepeatPolicy {
    static let nativeLike = Self(
        initialDelay: 0.38,
        characterPhaseEnd: 1.2,
        wordPhaseEnd: 2.8,
        sentencePhaseEnd: 4.2
    )

    let initialDelay: TimeInterval
    let characterPhaseEnd: TimeInterval
    let wordPhaseEnd: TimeInterval
    let sentencePhaseEnd: TimeInterval

    func stage(elapsed: TimeInterval) -> BackspaceRepeatStage? {
        guard elapsed >= initialDelay else { return nil }

        if elapsed < characterPhaseEnd {
            return BackspaceRepeatStage(unit: .character, interval: 0.055)
        }
        if elapsed < wordPhaseEnd {
            return BackspaceRepeatStage(unit: .word, interval: 0.16)
        }
        if elapsed < sentencePhaseEnd {
            return BackspaceRepeatStage(unit: .sentence, interval: 0.34)
        }
        return BackspaceRepeatStage(unit: .availableContext, interval: 0.55)
    }
}
