import Foundation

/// The word the cursor is sitting in, split at the insertion point.
struct CursorWord: Equatable {
    /// The whole word (`before` + `after`).
    let word: String
    /// The part of the word to the left of the cursor.
    let before: String
    /// The part of the word to the right of the cursor.
    let after: String
}

/// Decides, from the text on either side of the cursor, whether the cursor is *in a
/// word* (so we should offer corrections for that word) or *at a boundary* (so we should
/// offer next-word suggestions).
///
/// The rule is the character immediately before the cursor: a word character means the
/// cursor is at or inside a word; whitespace or punctuation means it's at a boundary.
/// So `আমি| বলি` edits "আমি", while `আমি |বলি` (space before the cursor) is a boundary —
/// even though a word begins immediately to the right.
enum CursorWordDetector {
    static func wordAtCursor(before: String, after: String) -> CursorWord? {
        // Trailing run of word characters immediately before the cursor.
        let beforeWord = String(before.reversed().prefix(while: { !isBoundary($0) }).reversed())
        guard !beforeWord.isEmpty else { return nil }
        // Leading run immediately after, so a cursor dropped mid-word still spans the whole word.
        let afterWord = String(after.prefix(while: { !isBoundary($0) }))
        return CursorWord(word: beforeWord + afterWord, before: beforeWord, after: afterWord)
    }

    /// A word boundary: whitespace, or punctuation such as the dari `।`.
    private static func isBoundary(_ character: Character) -> Bool {
        if character.isWhitespace { return true }
        return character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
                || scalar == "\u{0964}" // dari
        }
    }
}
