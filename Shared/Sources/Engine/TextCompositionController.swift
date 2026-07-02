import Foundation

@MainActor
protocol TextDocumentEditing {
    var contextBeforeInput: String? { get }

    func insertText(_ text: String)
    func setMarkedText(_ text: String, selectedRange: NSRange)
    func unmarkText()
}

@MainActor
final class TextCompositionController {
    private var markedText = ""

    var hasMarkedText: Bool {
        !markedText.isEmpty
    }

    func resetHostState() {
        markedText.removeAll(keepingCapacity: true)
    }

    func updateMarkedText(_ text: String, in document: TextDocumentEditing) {
        guard !text.isEmpty else {
            clearMarkedText(in: document)
            return
        }
        guard markedText != text else {
            return
        }

        document.setMarkedText(text, selectedRange: endSelectionRange(for: text))
        markedText = text
    }

    @discardableResult
    func commitText(_ text: String, trailingText: String = "", in document: TextDocumentEditing) -> Bool {
        guard !text.isEmpty else { return false }

        let committedText = text + trailingText
        if hasMarkedText {
            if markedText != committedText {
                document.setMarkedText(committedText, selectedRange: endSelectionRange(for: committedText))
            }
            document.unmarkText()
        } else {
            document.insertText(committedText)
        }
        markedText.removeAll(keepingCapacity: true)
        return true
    }

    func commitSuggestion(_ text: String, in document: TextDocumentEditing) {
        guard !text.isEmpty else { return }
        commitText(text, in: document)
    }

    func commitNextWordSuggestion(_ text: String, in document: TextDocumentEditing) {
        guard !text.isEmpty else { return }
        if let previous = document.contextBeforeInput?.last, !previous.isWhitespace {
            document.insertText(" ")
        }
        document.insertText(text)
        document.insertText(" ")
    }

    func insertSpaceIfNeeded(in document: TextDocumentEditing) {
        if let previous = document.contextBeforeInput?.last, previous.isWhitespace {
            return
        }
        document.insertText(" ")
    }

    func clearMarkedText(in document: TextDocumentEditing) {
        guard hasMarkedText else { return }
        document.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        document.unmarkText()
        markedText.removeAll(keepingCapacity: true)
    }

    private func endSelectionRange(for text: String) -> NSRange {
        NSRange(location: text.utf16.count, length: 0)
    }
}
