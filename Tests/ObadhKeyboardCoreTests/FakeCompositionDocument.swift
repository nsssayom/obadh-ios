import Foundation
@testable import ObadhKeyboardCore

@MainActor
final class FakeCompositionDocument: TextDocumentEditing {
    enum Operation: Equatable {
        case insertText(String)
        case setMarkedText(String)
        case unmarkText
    }

    private(set) var text = ""
    private var markedRange: Range<String.Index>?
    private(set) var operations: [Operation] = []

    var contextBeforeInput: String? {
        text
    }

    init(initialText: String = "") {
        text = initialText
    }

    func insertText(_ text: String) {
        replaceMarkedTextIfNeeded(with: "")
        self.text.append(text)
        operations.append(.insertText(text))
    }

    func setMarkedText(_ text: String, selectedRange: NSRange) {
        replaceMarkedTextIfNeeded(with: text)
        operations.append(.setMarkedText(text))
    }

    func unmarkText() {
        markedRange = nil
        operations.append(.unmarkText)
    }

    private func replaceMarkedTextIfNeeded(with replacement: String) {
        if let markedRange {
            text.replaceSubrange(markedRange, with: replacement)
        } else {
            text.append(replacement)
        }
        if replacement.isEmpty {
            markedRange = nil
        } else {
            markedRange = text.index(text.endIndex, offsetBy: -replacement.count)..<text.endIndex
        }
    }
}
