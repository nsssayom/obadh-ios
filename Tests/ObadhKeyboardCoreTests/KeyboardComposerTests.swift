import Foundation
import XCTest
@testable import ObadhKeyboardCore

@MainActor
final class KeyboardComposerTests: XCTestCase {
    func testActiveInputFeedsMarkedTextAndCommitsOnce() {
        let composer = KeyboardComposer(engine: FixtureEngine())
        let document = FakeCompositionDocument()
        let compositionController = TextCompositionController()

        composer.append("k")
        compositionController.updateMarkedText(composer.preview, in: document)
        composer.append("a")
        compositionController.updateMarkedText(composer.preview, in: document)
        composer.append("n")
        compositionController.updateMarkedText(composer.preview, in: document)

        XCTAssertEqual(document.text, "কান")
        XCTAssertEqual(document.operations, [
            .setMarkedText("ক"),
            .setMarkedText("কা"),
            .setMarkedText("কান")
        ])

        let committed = composer.commitActiveInput()
        XCTAssertEqual(committed, "কান")
        compositionController.commitText(committed ?? "", trailingText: " ", in: document)

        XCTAssertEqual(document.text, "কান ")
        XCTAssertEqual(document.operations, [
            .setMarkedText("ক"),
            .setMarkedText("কা"),
            .setMarkedText("কান"),
            .setMarkedText("কান "),
            .unmarkText
        ])
    }

    func testDeterministicOutputStaysDefaultCommitWhenAutocorrectRanksFirst() {
        let composer = KeyboardComposer(engine: AutocorrectFirstFixtureEngine())

        for scalar in "madar" {
            composer.append(String(scalar))
        }

        XCTAssertEqual(
            composer.activeSuggestions.map(\.text),
            ["মাদার", "তাদের", "থাকার"]
        )
        XCTAssertEqual(composer.activeSuggestions.first?.source, .deterministic)
        XCTAssertEqual(composer.commitActiveInput(), "মাদার")
    }
}

private struct FixtureEngine: BanglaTypingEngine {
    func transliterate(_ input: String) -> String {
        switch input {
        case "k":
            "ক"
        case "ka":
            "কা"
        case "kan":
            "কান"
        default:
            ""
        }
    }

    func compositionSuggestions(for romanInput: String, limit: Int) -> [String] {
        switch romanInput {
        case "k":
            ["ক"]
        case "ka":
            ["কা"]
        case "kan":
            ["কান"]
        default:
            []
        }
    }

    func autosuggestSuggestions(for context: String, limit: Int) -> [String] {
        []
    }
}

private struct AutocorrectFirstFixtureEngine: BanglaTypingEngine {
    func transliterate(_ input: String) -> String {
        input == "madar" ? "মাদার" : ""
    }

    func compositionSuggestions(for romanInput: String, limit: Int) -> [String] {
        romanInput == "madar" ? ["তাদের", "মাদার", "থাকার", "খাবার"] : []
    }

    func autosuggestSuggestions(for context: String, limit: Int) -> [String] {
        []
    }
}
