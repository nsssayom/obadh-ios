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
        let engine = AutocorrectFirstFixtureEngine()
        let composer = KeyboardComposer(engine: engine)

        for scalar in "madar" {
            composer.append(String(scalar))
        }

        // Autocorrect candidates arrive asynchronously in the app; here we merge
        // them directly to assert the deterministic entry stays first.
        composer.mergeAutocorrectCandidates(
            engine.compositionSuggestions(for: "madar", limit: composer.autocorrectFetchLimit),
            generation: composer.generation
        )

        XCTAssertEqual(
            composer.activeSuggestions.map(\.text),
            ["মাদার", "তাদের", "থাকার"]
        )
        XCTAssertEqual(composer.activeSuggestions.first?.source, .deterministic)
        XCTAssertEqual(composer.commitActiveInput(), "মাদার")
    }

    func testDeterministicPreviewIsAvailableBeforeAutocorrectMerges() {
        let composer = KeyboardComposer(engine: AutocorrectFirstFixtureEngine())

        for scalar in "madar" {
            composer.append(String(scalar))
        }

        // Before any async merge, only the deterministic preview is present.
        XCTAssertEqual(composer.preview, "মাদার")
        XCTAssertEqual(composer.activeSuggestions.map(\.text), ["মাদার"])
    }

    func testDoubleQRewritesToChandrabinduMarker() {
        let composer = KeyboardComposer(engine: FixtureEngine())

        composer.append("q")
        composer.append("q")
        XCTAssertEqual(composer.romanBuffer, "^")

        composer.clear()
        for scalar in "aqq" { composer.append(String(scalar)) }
        XCTAssertEqual(composer.romanBuffer, "a^")

        composer.clear()
        composer.append("q")
        XCTAssertEqual(composer.romanBuffer, "q", "a single q must be untouched")
    }

    func testEmojiSuggestionsAreExposedSeparatelyFromText() {
        let composer = KeyboardComposer(
            engine: AutocorrectFirstFixtureEngine(),
            emojiSuggester: FixtureEmojiSuggester(["মাদার": ["❤️", "😍", "🥰"]])
        )
        for scalar in "madar" { composer.append(String(scalar)) }

        XCTAssertEqual(composer.preview, "মাদার")
        XCTAssertEqual(composer.activeEmojis, ["❤️", "😍", "🥰"])
        // Emoji are a separate channel; text candidates never contain them.
        XCTAssertEqual(composer.activeSuggestions.first?.source, .deterministic)
        XCTAssertFalse(composer.activeSuggestions.contains { $0.text == "❤️" })
    }

    func testEmojiDoesNotDisturbTextCandidates() {
        let engine = AutocorrectFirstFixtureEngine()
        let composer = KeyboardComposer(engine: engine, emojiSuggester: FixtureEmojiSuggester(["মাদার": ["❤️"]]))
        for scalar in "madar" { composer.append(String(scalar)) }
        composer.mergeAutocorrectCandidates(
            engine.compositionSuggestions(for: "madar", limit: composer.autocorrectFetchLimit),
            generation: composer.generation
        )

        XCTAssertEqual(composer.activeSuggestions.first?.source, .deterministic)
        XCTAssertTrue(composer.activeSuggestions.contains { $0.source == .autocorrect })
        XCTAssertEqual(composer.activeEmojis, ["❤️"])
    }

    func testNoEmojiWithoutAMatch() {
        let composer = KeyboardComposer(engine: FixtureEngine(), emojiSuggester: FixtureEmojiSuggester([:]))
        composer.append("k")
        XCTAssertTrue(composer.activeEmojis.isEmpty)
    }

    func testStaleAutocorrectCandidatesAreIgnored() {
        let composer = KeyboardComposer(engine: FixtureEngine())

        composer.append("k")
        let staleGeneration = composer.generation
        composer.append("a")

        composer.mergeAutocorrectCandidates(["ক্যাব"], generation: staleGeneration)

        XCTAssertEqual(composer.activeSuggestions.map(\.text), ["কা"])
    }

    func testAutosuggestMergeKeepsSessionFirstAndFallsBackToContext() {
        let session = [
            KeyboardSuggestion(text: "আমি", source: .autosuggest),
            KeyboardSuggestion(text: "আমার", source: .autosuggest)
        ]
        let context = [
            KeyboardSuggestion(text: "আমার", source: .autosuggest),
            KeyboardSuggestion(text: "সে", source: .autosuggest),
            KeyboardSuggestion(text: "তুমি", source: .autosuggest)
        ]

        XCTAssertEqual(
            KeyboardComposer.mergeSuggestions(primary: session, fallback: context, limit: 3),
            [
                KeyboardSuggestion(text: "আমি", source: .autosuggest),
                KeyboardSuggestion(text: "আমার", source: .autosuggest),
                KeyboardSuggestion(text: "সে", source: .autosuggest)
            ]
        )
    }
}

private struct FixtureEmojiSuggester: BanglaEmojiSuggesting {
    let map: [String: [String]]

    init(_ map: [String: [String]]) {
        self.map = map
    }

    func emojis(for banglaWord: String) -> [String] {
        map[banglaWord] ?? []
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
