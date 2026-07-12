import XCTest
@testable import ObadhKeyboardCore

final class CursorWordDetectorTests: XCTestCase {
    private func detect(_ before: String, _ after: String) -> CursorWord? {
        CursorWordDetector.wordAtCursor(before: before, after: after)
    }

    /// Cursor at the end of a word (word char immediately before) → that word.
    func testCursorAtEndOfWord() {
        // "আমি| বলি" — cursor right after আমি.
        XCTAssertEqual(detect("আমি", " বলি"), CursorWord(word: "আমি", before: "আমি", after: ""))
    }

    /// Cursor after a space (boundary) → no word, even with a word to the right.
    func testCursorAfterSpaceIsBoundary() {
        // "আমি |বলি" — space before the cursor.
        XCTAssertNil(detect("আমি ", "বলি"))
    }

    /// Cursor dropped inside a word → the whole word, split at the cursor.
    func testCursorInsideWordSpansWholeWord() {
        // "আ|মি বলি"
        XCTAssertEqual(detect("আ", "মি বলি"), CursorWord(word: "আমি", before: "আ", after: "মি"))
    }

    /// Mid-sentence: only the word the cursor is in, bounded by the surrounding spaces.
    func testMidSentenceWordIsIsolated() {
        // "আমার বলার কি| চিলোনা" — cursor after কি.
        XCTAssertEqual(
            detect("আমার বলার কি", " চিলোনা"),
            CursorWord(word: "কি", before: "কি", after: "")
        )
    }

    /// Punctuation bounds a word: cursor after a comma is a boundary.
    func testPunctuationIsABoundary() {
        XCTAssertNil(detect("আমার,", " বলি"))
        // But right before the comma, the word is available.
        XCTAssertEqual(detect("আমার", ", বলি"), CursorWord(word: "আমার", before: "আমার", after: ""))
    }

    /// Empty before (start of field) → no word.
    func testStartOfFieldIsBoundary() {
        XCTAssertNil(detect("", "আমি"))
    }

    /// Latin behaves the same, for good measure.
    func testLatinWordAtCursor() {
        XCTAssertEqual(detect("hel", "lo there"), CursorWord(word: "hello", before: "hel", after: "lo"))
    }
}
