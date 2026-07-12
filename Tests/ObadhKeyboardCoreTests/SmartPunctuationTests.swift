import XCTest
@testable import ObadhKeyboardCore

final class SmartPunctuationTests: XCTestCase {
    func testDoubleHyphenBecomesEmDash() {
        let result = SmartPunctuation.literalSubstitution(for: "-", contextBefore: "কথা-")
        XCTAssertEqual(result, SmartPunctuationResult(deleteBefore: 1, insertion: "—"))
    }

    func testSingleHyphenPassesThrough() {
        let result = SmartPunctuation.literalSubstitution(for: "-", contextBefore: "কথা")
        XCTAssertEqual(result, .insert("-"))
    }

    func testThirdHyphenDoesNotRetriggerOnEmDash() {
        let result = SmartPunctuation.literalSubstitution(for: "-", contextBefore: "কথা—")
        XCTAssertEqual(result, .insert("-"))
    }

    func testThreeDotsBecomeEllipsis() {
        // First two dots pass through; the third collapses all three into "…".
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: ".", contextBefore: "কি"), .insert("."))
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: ".", contextBefore: "কি."), .insert("."))
        XCTAssertEqual(
            SmartPunctuation.literalSubstitution(for: ".", contextBefore: "কি.."),
            SmartPunctuationResult(deleteBefore: 2, insertion: "…")
        )
    }

    func testCurlyDoubleQuotesByContext() {
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: "\"", contextBefore: ""), .insert("\u{201C}"))
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: "\"", contextBefore: "সে বলল "), .insert("\u{201C}"))
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: "\"", contextBefore: "সে বলল \u{201C}কথা"), .insert("\u{201D}"))
    }

    func testCurlySingleQuotesByContext() {
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: "'", contextBefore: ""), .insert("\u{2018}"))
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: "'", contextBefore: "it"), .insert("\u{2019}"))
    }

    func testTakaAndOtherSymbolsPassThrough() {
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: "৳", contextBefore: "দাম "), .insert("৳"))
        XCTAssertEqual(SmartPunctuation.literalSubstitution(for: ",", contextBefore: "কথা"), .insert(","))
    }

    func testDoubleSpaceAfterWordBecomesDari() {
        let result = SmartPunctuation.doubleSpaceSubstitution(contextBefore: "আমি ")
        XCTAssertEqual(result, SmartPunctuationResult(deleteBefore: 1, insertion: "। "))
    }

    func testDoubleSpaceDoesNotFireAfterPunctuationOrSpace() {
        XCTAssertNil(SmartPunctuation.doubleSpaceSubstitution(contextBefore: "আমি। "))
        XCTAssertNil(SmartPunctuation.doubleSpaceSubstitution(contextBefore: "আমি  "))
        XCTAssertNil(SmartPunctuation.doubleSpaceSubstitution(contextBefore: "আমি"))
    }
}
