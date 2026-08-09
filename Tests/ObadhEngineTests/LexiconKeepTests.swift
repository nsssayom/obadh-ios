import Foundation
import Testing

private final class KeepBundleToken {}

/// Pins the premise behind issue #19 (fixed in observeCommittedToken): the words the frequency-ratio auto-insert
/// gate is designed to correct are themselves lexicon entries, so gating explicit
/// keeps behind `isLexiconWord` silences protection for exactly the main case.
@Suite(.serialized)
struct LexiconKeepTests {
    let engine = ObadhBridgeClient.shared

    init() {
        _ = ObadhBridgeClient.shared.configureModels(in: Bundle(for: KeepBundleToken.self))
    }

    @Test(arguments: [
        ("মানুস", "মানুষ"),
        ("বন্দু", "বন্ধু"),
    ])
    func gateTargetsAreThemselvesLexiconWords(typed: String, corrected: String) {
        let typedFrequency = engine.wordFrequency(typed)
        let correctedFrequency = engine.wordFrequency(corrected)
        // Both in the lexicon, the typed one far rarer: exactly the shape the
        // frequency-ratio gate fires on.
        #expect(engine.isLexiconWord(typed), "\(typed) is not a lexicon word")
        #expect(typedFrequency > 0)
        #expect(correctedFrequency > typedFrequency * 100)
    }
}
