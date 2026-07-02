import Foundation

enum BackspaceDeletionUnit: Equatable {
    case character
    case word
    case sentence
    case availableContext
}

struct BackspaceDeletionPlanner {
    static func deleteCount(before context: String, unit: BackspaceDeletionUnit) -> Int {
        guard !context.isEmpty else { return 0 }

        switch unit {
        case .character:
            return 1
        case .word:
            return wordDeleteCount(before: context)
        case .sentence:
            return sentenceDeleteCount(before: context)
        case .availableContext:
            return context.count
        }
    }

    private static func wordDeleteCount(before context: String) -> Int {
        let characters = Array(context)
        var index = characters.endIndex

        while index > characters.startIndex {
            let previous = characters.index(before: index)
            if !isBoundary(characters[previous]) {
                break
            }
            index = previous
        }

        while index > characters.startIndex {
            let previous = characters.index(before: index)
            if isBoundary(characters[previous]) {
                break
            }
            index = previous
        }

        let count = characters.distance(from: index, to: characters.endIndex)
        return max(count, 1)
    }

    private static func sentenceDeleteCount(before context: String) -> Int {
        let characters = Array(context)
        var index = characters.endIndex

        while index > characters.startIndex {
            let previous = characters.index(before: index)
            if !characters[previous].isWhitespace {
                break
            }
            index = previous
        }

        while index > characters.startIndex {
            let previous = characters.index(before: index)
            if isSentenceBoundary(characters[previous]) {
                break
            }
            index = previous
        }

        let count = characters.distance(from: index, to: characters.endIndex)
        return max(count, 1)
    }

    private static func isBoundary(_ character: Character) -> Bool {
        character.isWhitespace || character.isPunctuationLike
    }

    private static func isSentenceBoundary(_ character: Character) -> Bool {
        character == "।" || character == "." || character == "!" || character == "?" || character.isNewline
    }
}

private extension Character {
    var isPunctuationLike: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar) || scalar == "\u{0964}"
        }
    }
}
