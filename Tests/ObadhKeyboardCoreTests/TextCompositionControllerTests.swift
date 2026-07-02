import Foundation
import XCTest
@testable import ObadhKeyboardCore

@MainActor
final class TextCompositionControllerTests: XCTestCase {
    func testMarkedTextUpdatesAndCommitsWithSingleTrailingSpace() {
        let document = FakeCompositionDocument()
        let controller = TextCompositionController()

        controller.updateMarkedText("ক", in: document)
        controller.updateMarkedText("কা", in: document)
        controller.updateMarkedText("কান", in: document)
        controller.commitText("কান", trailingText: " ", in: document)

        XCTAssertEqual(document.text, "কান ")
        XCTAssertEqual(document.operations, [
            .setMarkedText("ক"),
            .setMarkedText("কা"),
            .setMarkedText("কান"),
            .setMarkedText("কান "),
            .unmarkText
        ])
    }

    func testRedundantMarkedTextUpdateIsSkipped() {
        let document = FakeCompositionDocument()
        let controller = TextCompositionController()

        controller.updateMarkedText("কান", in: document)
        controller.updateMarkedText("কান", in: document)

        XCTAssertEqual(document.text, "কান")
        XCTAssertEqual(document.operations, [.setMarkedText("কান")])
    }

    func testBackspaceToEmptyClearsMarkedText() {
        let document = FakeCompositionDocument()
        let controller = TextCompositionController()

        controller.updateMarkedText("কা", in: document)
        controller.updateMarkedText("", in: document)

        XCTAssertEqual(document.text, "")
        XCTAssertEqual(document.operations, [
            .setMarkedText("কা"),
            .setMarkedText(""),
            .unmarkText
        ])
    }

    func testSuggestionReplacesActiveMarkedTextWithoutTrailingSpace() {
        let document = FakeCompositionDocument()
        let controller = TextCompositionController()

        controller.updateMarkedText("সুশিল", in: document)
        controller.commitSuggestion("সুশীল", in: document)

        XCTAssertEqual(document.text, "সুশীল")
        XCTAssertEqual(document.operations, [
            .setMarkedText("সুশিল"),
            .setMarkedText("সুশীল"),
            .unmarkText
        ])
    }

    func testNextWordSuggestionInsertsReadableBoundary() {
        let document = FakeCompositionDocument(initialText: "আমি")
        let controller = TextCompositionController()

        controller.commitNextWordSuggestion("ভালো", in: document)

        XCTAssertEqual(document.text, "আমি ভালো ")
        XCTAssertEqual(document.operations, [
            .insertText(" "),
            .insertText("ভালো"),
            .insertText(" ")
        ])
    }

    func testNextWordSuggestionDoesNotDoubleLeadingSpace() {
        let document = FakeCompositionDocument(initialText: "আমি ")
        let controller = TextCompositionController()

        controller.commitNextWordSuggestion("ভালো", in: document)

        XCTAssertEqual(document.text, "আমি ভালো ")
        XCTAssertEqual(document.operations, [
            .insertText("ভালো"),
            .insertText(" ")
        ])
    }

    func testIdleDoubleSpaceIsSuppressed() {
        let document = FakeCompositionDocument()
        let controller = TextCompositionController()

        controller.insertSpaceIfNeeded(in: document)
        controller.insertSpaceIfNeeded(in: document)

        XCTAssertEqual(document.text, " ")
        XCTAssertEqual(document.operations, [.insertText(" ")])
    }
}
