import Foundation

struct PunctuationRenderOperation: Equatable {
    let deletePreviousCharacterCount: Int
    let insertion: String
}

final class KeyboardPunctuationBuffer {
    private var baseContext = ""
    private var rawBuffer = ""
    private var renderedBuffer = ""

    func append(
        _ rawScalar: String,
        contextBeforeInput: String,
        engine: BanglaTypingEngine
    ) -> PunctuationRenderOperation {
        if rawBuffer.isEmpty {
            baseContext = contextBeforeInput
        }

        rawBuffer.append(rawScalar)
        let nextRendered = render(rawBuffer, after: baseContext, engine: engine)
        let operation = PunctuationRenderOperation(
            deletePreviousCharacterCount: renderedBuffer.count,
            insertion: nextRendered
        )
        renderedBuffer = nextRendered
        return operation
    }

    func reset() {
        baseContext.removeAll(keepingCapacity: true)
        rawBuffer.removeAll(keepingCapacity: true)
        renderedBuffer.removeAll(keepingCapacity: true)
    }

    private func render(_ rawText: String, after context: String, engine: BanglaTypingEngine) -> String {
        let renderedText = engine.transliterate(context + rawText)
        if renderedText.hasPrefix(context) {
            return String(renderedText.dropFirst(context.count))
        }
        return engine.transliterate(rawText)
    }
}
