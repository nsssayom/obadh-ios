import Foundation
import XCTest
@testable import ObadhKeyboardCore

@MainActor
final class KeyboardComposerTests: XCTestCase {
    func testActiveInputRendersAsTextAndCommitsOnce() {
        let composer = KeyboardComposer(engine: FixtureEngine())
        let document = FakeCompositionDocument()
        let compositionController = TextCompositionController()

        composer.append("k")
        compositionController.setComposition(composer.preview, in: document)
        composer.append("a")
        compositionController.setComposition(composer.preview, in: document)
        composer.append("n")
        compositionController.setComposition(composer.preview, in: document)

        XCTAssertEqual(document.text, "কান")
        // Each keystroke appends only the changed suffix — the word is ordinary text.
        XCTAssertEqual(document.operations, [
            .insertText("ক"),
            .insertText("া"),
            .insertText("ন")
        ])

        let committed = composer.commitActiveInput()
        XCTAssertEqual(committed, "কান")
        compositionController.commit(finalText: committed ?? "", trailingText: " ", in: document)

        XCTAssertEqual(document.text, "কান ")
        // The word is already real; commit only appends the space.
        XCTAssertEqual(document.operations, [
            .insertText("ক"),
            .insertText("া"),
            .insertText("ন"),
            .insertText(" ")
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

extension KeyboardComposerTests {
    /// Builds a composer at a word with a deterministic + one autocorrect candidate.
    private func composerWithCorrection() -> KeyboardComposer {
        let composer = KeyboardComposer(engine: BanhlaFixtureEngine())
        for scalar in "banhla" { composer.append(String(scalar)) }
        composer.mergeAutocorrectCandidates(
            ["বাংলা", "বনিহালা"], generation: composer.generation
        )
        return composer
    }

    /// Feature off: no target, so space commits exactly what is shown.
    func testNoAutocorrectTargetWhenFeatureOff() {
        let composer = composerWithCorrection()
        composer.resolveAutocorrectTarget(
            autoInsertEnabled: false,
            deterministicIsLexiconWord: false,
            isProtectedWord: { _ in false }
        )
        XCTAssertNil(composer.autocorrectTarget)
        XCTAssertEqual(composer.commitText, composer.preview) // the deterministic
    }

    /// Feature on, typed word isn't real, a correction exists: space commits the
    /// correction, and the shown deterministic word is what gets quoted.
    func testAutocorrectTargetIsTheTopCorrectionForAnUnknownWord() {
        let composer = composerWithCorrection()
        composer.resolveAutocorrectTarget(
            autoInsertEnabled: true,
            deterministicIsLexiconWord: false,
            isProtectedWord: { _ in false }
        )
        XCTAssertEqual(composer.autocorrectTarget, "বাংলা")
        XCTAssertEqual(composer.commitText, "বাংলা")
    }

    /// The typed word is already a real word: never second-guessed, even with the
    /// feature on.
    func testNoTargetWhenShownWordIsALexiconWord() {
        let composer = composerWithCorrection()
        composer.resolveAutocorrectTarget(
            autoInsertEnabled: true,
            deterministicIsLexiconWord: true,
            isProtectedWord: { _ in false }
        )
        XCTAssertNil(composer.autocorrectTarget)
    }

    /// A word the user has established is protected: no correction.
    func testNoTargetWhenShownWordIsProtected() {
        let composer = composerWithCorrection()
        composer.resolveAutocorrectTarget(
            autoInsertEnabled: true,
            deterministicIsLexiconWord: false,
            isProtectedWord: { $0 == composer.preview }
        )
        XCTAssertNil(composer.autocorrectTarget)
    }

    /// A keystroke invalidates a resolved target until fresh candidates re-resolve it.
    func testTargetClearsWhenTheBufferChanges() {
        let composer = composerWithCorrection()
        composer.resolveAutocorrectTarget(
            autoInsertEnabled: true,
            deterministicIsLexiconWord: false,
            isProtectedWord: { _ in false }
        )
        XCTAssertNotNil(composer.autocorrectTarget)

        composer.append("x")
        XCTAssertNil(composer.autocorrectTarget)
    }
}

private struct BanhlaFixtureEngine: BanglaTypingEngine {
    func transliterate(_ input: String) -> String {
        input == "banhla" ? "বানহ্লা" : (input.isEmpty ? "" : "বানহ্লা")
    }

    func compositionSuggestions(for romanInput: String, limit: Int) -> [String] {
        romanInput == "banhla" ? ["বাংলা", "বনিহালা"] : []
    }

    func autosuggestSuggestions(for context: String, limit: Int) -> [String] { [] }
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
