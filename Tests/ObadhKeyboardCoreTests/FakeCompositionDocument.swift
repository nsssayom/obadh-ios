import Foundation
@testable import ObadhKeyboardCore

/// A minimal in-memory stand-in for the host text field: text with a cursor at the end,
/// recording every edit so tests can assert the exact op sequence.
@MainActor
final class FakeCompositionDocument: TextDocumentEditing {
    enum Operation: Equatable {
        case insertText(String)
        case deleteBackward
    }

    private(set) var text = ""
    private(set) var operations: [Operation] = []

    init(initialText: String = "") {
        text = initialText
    }

    var contextBeforeInput: String? {
        text
    }

    func insertText(_ text: String) {
        self.text.append(text)
        operations.append(.insertText(text))
    }

    func deleteBackward() {
        if !text.isEmpty {
            text.removeLast()
        }
        operations.append(.deleteBackward)
    }
}
