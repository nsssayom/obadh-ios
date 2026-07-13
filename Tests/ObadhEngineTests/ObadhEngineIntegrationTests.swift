import Foundation
import Testing

/// Resolves the test bundle so the shipped model artifacts (`bn.fst`, the
/// autosuggest n-gram) can be located the same way the keyboard locates them.
private final class BundleToken {}

/// Real-engine integration tests (ABI v2 / engine 0.9.0).
///
/// Unlike the pure-logic unit suite (which runs under SwiftPM and cannot see the
/// xcframework), this target links `ObadhBridge.xcframework` and bundles the real
/// `ObadhModels` artifacts, so it exercises the actual Swift↔C boundary: opaque-
/// handle lifecycle, the count+length-prefixed record-list decoding, snprintf-style
/// sizing, `word_frequency`, and the fingerprint surface. These are the tests that
/// catch a marshalling regression an engine bump could introduce.
///
/// Serialized because the snapshot test mutates the shared personal-overlay handle.
@Suite(.serialized)
struct ObadhEngineIntegrationTests {
    let engine = ObadhBridgeClient.shared
    let configuration: ObadhModelConfiguration

    init() {
        // Idempotent: opens the handles once, then no-ops on later instances.
        configuration = ObadhBridgeClient.shared.configureModels(in: Bundle(for: BundleToken.self))
    }

    // MARK: - Configuration

    @Test func modelsLoadFromTheBundledArtifacts() {
        #expect(configuration.autocorrectAvailable)
        #expect(configuration.autosuggestAvailable)
    }

    // MARK: - Deterministic transliteration (goldens)

    @Test(arguments: [
        ("ami", "আমি"),
        ("bangla", "বাংলা"),
        ("banhla", "বানহ্লা"),
        ("kan", "কান"),
        ("", ""),
    ])
    func transliterates(roman: String, expected: String) {
        #expect(engine.transliterate(roman) == expected)
    }

    // MARK: - Compose bar (record-list decoding + baseline-first)

    @Test func composeLeadsWithTheDeterministicBaselineAndDecodesMultipleRecords() {
        let baseline = engine.transliterate("banhla")
        let candidates = engine.compositionSuggestions(for: "banhla", limit: 5)
        #expect(candidates.first == baseline)   // the baseline always leads
        #expect(candidates.count >= 2)           // a multi-record list decoded correctly
        #expect(candidates.contains("বাংলা"))    // the correction is offered behind it
        #expect(!candidates.contains(""))        // framing never yields an empty candidate
    }

    /// Baseline-first is a hard invariant of the compose channel, so it must hold
    /// across a sweep of unrelated inputs — a cheap regression net for the record
    /// framing and the ranker wiring.
    @Test(arguments: ["ami", "tumi", "bangla", "banhla", "boi", "kemon", "bhalo", "pani"])
    func composeBaselineFirstInvariantHolds(roman: String) {
        let baseline = engine.transliterate(roman)
        let candidates = engine.compositionSuggestions(for: roman, limit: 5)
        #expect(candidates.first == baseline)
        #expect(!candidates.contains(""))
    }

    // MARK: - Lexicon frequency (the ratio-gate foundation) + membership

    /// `word_frequency` returns the stored count, 0 for a non-entry. Pinned to the
    /// real `bn.fst` — these are the exact numbers a frequency-ratio auto-insert
    /// gate divides (baseline vs correction), so a shift here would move the gate.
    @Test func wordFrequencyReturnsPinnedCounts() {
        #expect(engine.wordFrequency("বাংলা") == 137_381)
        #expect(engine.wordFrequency("মানুস") == 49)     // the rare typo entry the ratio overrides
        #expect(engine.wordFrequency("যযযযযয") == 0)     // absent → 0 sentinel
    }

    @Test func lexiconMembershipDistinguishesRealWordsFromNonsense() {
        #expect(engine.isLexiconWord("বাংলা"))           // wordFrequency > 0
        #expect(!engine.isLexiconWord("যযযযযয"))
    }

    @Test func wordAlternativesForARealWordAreNonEmpty() {
        #expect(!engine.wordAlternatives(for: "বাংলা", limit: 4).isEmpty)
    }

    // MARK: - Personal overlay snapshot round-trip

    /// Commit a learned word, export the overlay, clear it, and import it back —
    /// exercising commit + snapshot export/import across the boundary.
    @Test func personalSnapshotRoundTripsThroughExportAndImport() throws {
        let word = "খটখটানয়" // out-of-vocabulary nonce
        engine.clearPersonalAutosuggest()
        #expect(engine.commitAutosuggestToken(word))

        let snapshot = try #require(engine.exportPersonalAutosuggestSnapshot())
        #expect(!snapshot.isEmpty)

        engine.clearPersonalAutosuggest()
        #expect(engine.importPersonalAutosuggestSnapshot(snapshot))
    }

    // MARK: - Artifact fingerprints (pinned; catch a silent data swap on a bump)

    /// The engine exposes a content hash of each artifact. Pinning it makes an
    /// unintended artifact change on an engine bump fail loudly here instead of
    /// silently altering suggestions. Update deliberately when the bundled `data/`
    /// submodule is revved. (Unchanged 0.8.1 → 0.9.0 — 0.9.0 is an ABI-only reshape.)
    @Test func artifactFingerprintsMatchThePinnedArtifacts() {
        #expect(engine.autocorrectFingerprint() == Self.pinnedAutocorrectFingerprint)
        #expect(engine.autosuggestFingerprint() == Self.pinnedAutosuggestFingerprint)
    }

    static let pinnedAutocorrectFingerprint: UInt64 = 16_395_964_778_339_222_933
    static let pinnedAutosuggestFingerprint: UInt64 = 12_903_309_268_127_864_731
}
