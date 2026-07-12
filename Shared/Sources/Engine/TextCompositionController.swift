import Foundation

@MainActor
protocol TextDocumentEditing {
    var contextBeforeInput: String? { get }

    func insertText(_ text: String)
    func deleteBackward()
}

/// Renders the word being composed as ordinary document text and rewrites it in place
/// as the user types, rather than holding it as marked text.
///
/// Marked text is an IME composition that binds the insertion point to itself until
/// confirmed, so the cursor cannot leave a half-typed word — and freeing it depends on
/// each host delivering selection callbacks, which many don't. Inserting real text and
/// re-deriving it sidesteps all of that: the word is always committed text, the cursor
/// moves freely, switching keyboards keeps the word for nothing, and there is no marked
/// region to strand.
///
/// The only state is `composedText`: the exact string we last inserted for the current
/// word. Every rewrite verifies that string is still at the cursor before touching it,
/// so a cursor move or a host edit we didn't observe can never make us delete text we
/// don't own — at worst we start a fresh word.
@MainActor
final class TextCompositionController {
    private(set) var composedText = ""

    var hasActiveComposition: Bool {
        !composedText.isEmpty
    }

    /// Forget the current word without touching the document. The text stays as-is (it
    /// is already real), so this is what to call when the cursor moves, the keyboard is
    /// switched away, or the host rewrites the field.
    func resetHostState() {
        composedText = ""
    }

    /// Make the current word read as `text`, replacing whatever we last inserted for it.
    ///
    /// Deletes only the changed suffix (keeping the common prefix) to minimise edits and
    /// visible flicker. If our tracked word is no longer at the cursor — the user moved,
    /// or the host changed the text — we abandon it untouched and insert `text` fresh.
    func setComposition(_ text: String, in document: TextDocumentEditing) {
        let current = composedText
        let context = document.contextBeforeInput ?? ""

        if !current.isEmpty, !context.hasSuffix(current) {
            // Our word is not where we left it. Don't delete whatever is now at the
            // cursor; treat this as a brand-new composition.
            composedText = ""
            if !text.isEmpty {
                document.insertText(text)
            }
            composedText = text
            return
        }

        // Fast path: the new rendering only appends scalars to the old one — a vowel sign
        // or nasal joining the current cluster, the common case while typing. Insert just
        // the tail; it re-clusters on screen with no delete, so there is no flicker.
        // (A grapheme prefix would miss this: "বা" is not a Character-prefix of "বাং".)
        if text.unicodeScalars.starts(with: current.unicodeScalars) {
            let tail = String(text.unicodeScalars.dropFirst(current.unicodeScalars.count))
            if !tail.isEmpty {
                document.insertText(tail)
            }
            composedText = text
            return
        }

        // General case (a reshape, a shortening, or a correction replacing the word):
        // remove the changed suffix, then insert the new one. The suffix is deleted
        // against the LIVE document, not by counting our own grapheme clusters —
        // deleteBackward's unit is the host's, and a Bangla conjunct may be one press or
        // several. Counting graphemes and trusting the count is what left half-replaced
        // words like "বানহবাংলা". Scalars decrease monotonically however the host chunks
        // a delete, so we delete until the document's scalar length reaches where the
        // shared (grapheme-aligned) prefix ends.
        let keep = current.commonPrefix(with: text)
        let removeScalars = current.unicodeScalars.count - keep.unicodeScalars.count
        let targetScalars = context.unicodeScalars.count - removeScalars
        var budget = removeScalars + 8   // guard against a host that never shrinks
        while budget > 0, (document.contextBeforeInput?.unicodeScalars.count ?? 0) > targetScalars {
            document.deleteBackward()
            budget -= 1
        }
        let insertion = String(text[keep.endIndex...])
        if !insertion.isEmpty {
            document.insertText(insertion)
        }
        composedText = text
    }

    /// Finalize the current word, optionally replacing it with `finalText` (an
    /// autocorrect pick differing from what is shown), then append `trailingText` (a
    /// space, a dari, a newline). The word is already real text, so with no replacement
    /// and no trailing text this is just dropping our tracking.
    @discardableResult
    func commit(finalText: String, trailingText: String = "", in document: TextDocumentEditing) -> Bool {
        if !finalText.isEmpty, finalText != composedText {
            setComposition(finalText, in: document)
        }
        if !trailingText.isEmpty {
            document.insertText(trailingText)
        }
        let didCommit = hasActiveComposition || !trailingText.isEmpty
        composedText = ""
        return didCommit
    }

    /// Replace the current word with an accepted suggestion, keeping it as plain text
    /// with no trailing space (the caller decides what follows).
    func commitSuggestion(_ text: String, in document: TextDocumentEditing) {
        guard !text.isEmpty else { return }
        setComposition(text, in: document)
        composedText = ""
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

    /// Delete the current word from the document (e.g. word-unit backspace mid-compose).
    func clearComposition(in document: TextDocumentEditing) {
        setComposition("", in: document)
    }
}
