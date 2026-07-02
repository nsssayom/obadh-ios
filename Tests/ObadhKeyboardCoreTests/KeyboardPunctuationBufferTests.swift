import XCTest
@testable import ObadhKeyboardCore

final class KeyboardPunctuationBufferTests: XCTestCase {
    func testPunctuationBufferUsesEngineRenderingForRepeatedPeriod() {
        let engine = PunctuationFixtureEngine()
        let buffer = KeyboardPunctuationBuffer()

        XCTAssertEqual(
            buffer.append(".", contextBeforeInput: "আমি", engine: engine),
            PunctuationRenderOperation(deletePreviousCharacterCount: 0, insertion: "।")
        )
        XCTAssertEqual(
            buffer.append(".", contextBeforeInput: "আমি।", engine: engine),
            PunctuationRenderOperation(deletePreviousCharacterCount: 1, insertion: "।।")
        )
        XCTAssertEqual(
            buffer.append(".", contextBeforeInput: "আমি।।", engine: engine),
            PunctuationRenderOperation(deletePreviousCharacterCount: 2, insertion: "...")
        )

        XCTAssertEqual(engine.inputs, ["আমি.", "আমি..", "আমি..."])
    }

    func testPunctuationBufferResetsBetweenRuns() {
        let engine = PunctuationFixtureEngine()
        let buffer = KeyboardPunctuationBuffer()

        _ = buffer.append(".", contextBeforeInput: "আমি", engine: engine)
        buffer.reset()

        XCTAssertEqual(
            buffer.append(".", contextBeforeInput: "তুমি", engine: engine),
            PunctuationRenderOperation(deletePreviousCharacterCount: 0, insertion: "।")
        )
        XCTAssertEqual(engine.inputs, ["আমি.", "তুমি."])
    }
}

private final class PunctuationFixtureEngine: BanglaTypingEngine {
    private(set) var inputs: [String] = []

    func transliterate(_ input: String) -> String {
        inputs.append(input)
        if input.hasSuffix("...") {
            return String(input.dropLast(3)) + "..."
        }
        if input.hasSuffix("..") {
            return String(input.dropLast(2)) + "।।"
        }
        if input.hasSuffix(".") {
            return String(input.dropLast()) + "।"
        }
        return input
    }

    func compositionSuggestions(for romanInput: String, limit: Int) -> [String] {
        []
    }

    func autosuggestSuggestions(for context: String, limit: Int) -> [String] {
        []
    }
}
