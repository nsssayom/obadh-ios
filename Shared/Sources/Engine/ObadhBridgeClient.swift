import Foundation
import ObadhBridge

struct ObadhModelConfiguration: Equatable {
    let autocorrectAvailable: Bool
    let autosuggestAvailable: Bool
}

/// Bridges Swift to the engine's C ABI (`obadh_engine`'s `cabi` feature — the
/// vendored `obadh.h`, ABI v2). The engine defines and owns every entry point;
/// this type only manages the opaque handles and marshals strings across the
/// boundary.
///
/// The ABI has no internal locking and forbids using a single handle from two
/// threads at once, so every call is serialized behind `lock`. Contention is nil
/// in practice — typing is main-thread and the async work runs on one serial
/// queue — but the lock makes the contract hold regardless of caller.
final class ObadhBridgeClient: BanglaTypingEngine, @unchecked Sendable {
    static let shared = ObadhBridgeClient()

    private let lock = NSLock()
    private var engineHandle: OpaquePointer?
    private var autocorrectHandle: OpaquePointer?
    private var autosuggestHandle: OpaquePointer?

    private init() {}

    deinit {
        // Never runs for the shared singleton, but keeps the handle lifecycle
        // correct (and the *_free symbols honestly used) if an instance is ever
        // created and released.
        if let engineHandle { obadh_engine_free(engineHandle) }
        if let autocorrectHandle { obadh_autocorrect_free(autocorrectHandle) }
        if let autosuggestHandle { obadh_autosuggest_free(autosuggestHandle) }
    }

    // MARK: - Configuration

    func configureModels(in bundle: Bundle) -> ObadhModelConfiguration {
        lock.lock()
        defer { lock.unlock() }

        assert(obadh_abi_version() == 2, "ObadhBridge built against a different engine C ABI")

        if engineHandle == nil {
            engineHandle = obadh_engine_new()
        }
        if autocorrectHandle == nil {
            autocorrectHandle = openAutocorrect(in: bundle)
        }
        if autosuggestHandle == nil {
            autosuggestHandle = openAutosuggest(in: bundle)
        }

        #if DEBUG
        print("[Obadh] autocorrect fingerprint: \(autocorrectFingerprintLocked()), autosuggest fingerprint: \(autosuggestFingerprintLocked())")
        #endif

        return ObadhModelConfiguration(
            autocorrectAvailable: autocorrectHandle != nil,
            autosuggestAvailable: autosuggestHandle != nil
        )
    }

    /// Content fingerprint of the loaded `bn.fst`, or 0 if unavailable. A stable
    /// hash of the artifact bytes: pin it in a test so a silent artifact swap on an
    /// engine bump fails loudly instead of degrading suggestions unnoticed.
    func autocorrectFingerprint() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return autocorrectFingerprintLocked()
    }

    /// Content fingerprint of the loaded autosuggest n-gram artifact, or 0 if
    /// unavailable. See `autocorrectFingerprint()`.
    func autosuggestFingerprint() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return autosuggestFingerprintLocked()
    }

    private func autocorrectFingerprintLocked() -> UInt64 {
        guard let autocorrectHandle else { return 0 }
        return obadh_autocorrect_fingerprint(autocorrectHandle)
    }

    private func autosuggestFingerprintLocked() -> UInt64 {
        guard let autosuggestHandle else { return 0 }
        return obadh_autosuggest_fingerprint(autosuggestHandle)
    }

    private func openAutocorrect(in bundle: Bundle) -> OpaquePointer? {
        guard
            let fstURL = bundle.url(
                forResource: "bn",
                withExtension: "fst",
                subdirectory: "ObadhModels/autocorrect"
            ),
            let loanwordURL = bundle.url(
                forResource: "en_bn_loanwords",
                withExtension: "fst",
                subdirectory: "ObadhModels/autocorrect"
            )
        else {
            return nil
        }

        let fstPath = Array(fstURL.path.utf8)
        let loanwordPath = Array(loanwordURL.path.utf8)
        return fstPath.withUnsafeBufferPointer { fstBuffer in
            loanwordPath.withUnsafeBufferPointer { loanwordBuffer in
                obadh_autocorrect_open(
                    fstBuffer.baseAddress,
                    fstBuffer.count,
                    loanwordBuffer.baseAddress,
                    loanwordBuffer.count
                )
            }
        }
    }

    private func openAutosuggest(in bundle: Bundle) -> OpaquePointer? {
        guard
            let artifactURL = bundle.url(
                forResource: "autosuggest-ngram-c64",
                withExtension: "bin",
                subdirectory: "ObadhModels/autosuggest"
            )
        else {
            return nil
        }
        let artifactPath = Array(artifactURL.path.utf8)
        return artifactPath.withUnsafeBufferPointer { artifactBuffer in
            obadh_autosuggest_open(artifactBuffer.baseAddress, artifactBuffer.count)
        }
    }

    // MARK: - Transliteration

    func transliterate(_ input: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let engineHandle else { return "" }
        var input = input
        return input.withUTF8 { inputBuffer in
            readString { outputPtr, capacity in
                obadh_transliterate(engineHandle, inputBuffer.baseAddress, inputBuffer.count, outputPtr, capacity)
            }
        }
    }

    // MARK: - Autocorrect

    /// The active-typing candidate bar: deterministic baseline first, then
    /// corrections. Always non-empty for real input so the user can keep exactly
    /// what they typed.
    func compositionSuggestions(for romanInput: String, limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let autocorrectHandle else { return [] }
        var romanInput = romanInput
        let boundedLimit = max(0, limit)
        return romanInput.withUTF8 { inputBuffer in
            readStringList { outputPtr, capacity in
                obadh_compose_suggestions(autocorrectHandle, inputBuffer.baseAddress, inputBuffer.count, boundedLimit, outputPtr, capacity)
            }
        }
    }

    /// Ranked corrections for `roman` with full provenance — the records the
    /// auto-insert gate is built on. Decodes the engine's packed list:
    /// [u32 count] then per record [u32 len][utf8][u8 source][u16 edit]
    /// [u16 repair, 0xFFFF = none][u64 frequency], all little-endian.
    func detailedCorrections(for romanInput: String, limit: Int) -> [DetailedCorrection] {
        lock.lock()
        defer { lock.unlock() }
        guard let autocorrectHandle else { return [] }
        var romanInput = romanInput
        let boundedLimit = max(0, limit)
        let bytes = romanInput.withUTF8 { inputBuffer in
            readBytes { outputPtr, capacity in
                obadh_autocorrect_suggest_detailed(
                    autocorrectHandle,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    boundedLimit,
                    outputPtr,
                    capacity
                )
            }
        }
        return Self.parseDetailedCorrections(bytes)
    }

    static func parseDetailedCorrections(_ bytes: [UInt8]) -> [DetailedCorrection] {
        guard bytes.count >= 4 else { return [] }
        func readUInt32(at offset: Int) -> Int {
            Int(UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24)
        }
        func readUInt16(at offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        }
        func readUInt64(at offset: Int) -> UInt64 {
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(bytes[offset + i]) << (8 * i)
            }
            return value
        }

        let count = readUInt32(at: 0)
        var offset = 4
        var items: [DetailedCorrection] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            guard offset + 4 <= bytes.count else { break }
            let length = readUInt32(at: offset)
            offset += 4
            guard offset + length + 1 + 2 + 2 + 8 <= bytes.count else { break }
            let text = String(decoding: bytes[offset..<offset + length], as: UTF8.self)
            offset += length
            let source = bytes[offset]
            offset += 1
            let editCost = readUInt16(at: offset)
            offset += 2
            let repairRaw = readUInt16(at: offset)
            offset += 2
            let frequency = readUInt64(at: offset)
            offset += 8
            items.append(DetailedCorrection(
                text: text,
                source: source,
                editCost: editCost,
                romanRepairCost: repairRaw == 0xFFFF ? nil : repairRaw,
                frequency: frequency
            ))
        }
        return items
    }

    /// Lexicon frequency of `word` (0 if it is not an entry). Presence is `> 0`;
    /// no entry is stored with frequency 0. The count is the baseline signal a
    /// frequency-ratio auto-insert gate needs.
    func wordFrequency(_ word: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let autocorrectHandle else { return 0 }
        var word = word
        return word.withUTF8 { buffer in
            obadh_autocorrect_word_frequency(autocorrectHandle, buffer.baseAddress, buffer.count)
        }
    }

    /// Whether `word` is an exact entry in the autocorrect lexicon (`bn.fst`).
    func isLexiconWord(_ word: String) -> Bool {
        wordFrequency(word) > 0
    }

    /// Lexicon alternatives for an already-committed Bangla word under the cursor
    /// (a re-correction menu; lexicon-only, no Roman repairs).
    func wordAlternatives(for banglaWord: String, limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let autocorrectHandle else { return [] }
        var banglaWord = banglaWord
        let boundedLimit = max(0, limit)
        return banglaWord.withUTF8 { buffer in
            readStringList { outputPtr, capacity in
                obadh_autocorrect_word_alternatives(autocorrectHandle, buffer.baseAddress, buffer.count, boundedLimit, outputPtr, capacity)
            }
        }
    }

    // MARK: - Autosuggest

    /// Stateless next-word suggestions for an explicit context (the mid-cursor
    /// path). Model-only — does not use or mutate the session's learned state.
    func autosuggestSuggestions(for context: String, limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle else { return [] }
        var context = context
        let boundedLimit = max(0, limit)
        return context.withUTF8 { buffer in
            readStringList { outputPtr, capacity in
                obadh_autosuggest_suggest_for_context(autosuggestHandle, buffer.baseAddress, buffer.count, boundedLimit, outputPtr, capacity)
            }
        }
    }

    /// Next-word suggestions for the current session context, with the personal
    /// overlay's learned words merged in.
    func autosuggestSessionSuggestions(limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle else { return [] }
        let boundedLimit = max(0, limit)
        return readStringList { outputPtr, capacity in
            obadh_autosuggest_suggest(autosuggestHandle, boundedLimit, outputPtr, capacity)
        }
    }

    /// Commit a token into the session context, learning it into the personal
    /// overlay. Word-protection for auto-insert lives app-side (`LearnedWordStore`).
    @discardableResult
    func commitAutosuggestToken(_ token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle else { return false }
        var token = token
        return token.withUTF8 { buffer in
            obadh_autosuggest_commit(autosuggestHandle, buffer.baseAddress, buffer.count) == 1
        }
    }

    func clearAutosuggestSession() {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle else { return }
        obadh_autosuggest_clear_session(autosuggestHandle)
    }

    func clearPersonalAutosuggest() {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle else { return }
        obadh_autosuggest_clear_personal(autosuggestHandle)
    }

    func exportPersonalAutosuggestSnapshot() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle else { return nil }
        let bytes = readBytes { outputPtr, capacity in
            obadh_autosuggest_export_personal(autosuggestHandle, outputPtr, capacity)
        }
        return bytes.isEmpty ? nil : Data(bytes)
    }

    @discardableResult
    func importPersonalAutosuggestSnapshot(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let autosuggestHandle, !data.isEmpty else { return false }
        return data.withUnsafeBytes { inputBuffer in
            obadh_autosuggest_import_personal(
                autosuggestHandle,
                inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                inputBuffer.count
            ) == 1
        }
    }

    // MARK: - Marshalling

    /// Words and suggestion lists are short, so a stack scratch buffer usually
    /// satisfies the whole call in a single crossing with zero heap allocation.
    private static let scratchCapacity = 1024

    /// Invokes a size-reporting C writer into a stack buffer, growing once only if
    /// the output does not fit. The ABI returns the required length and copies only
    /// when capacity is sufficient, so this is a single crossing in the common case.
    private func readBytes(_ write: (UnsafeMutablePointer<UInt8>?, Int) -> Int) -> [UInt8] {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Self.scratchCapacity) { scratch -> [UInt8] in
            let required = write(scratch.baseAddress, scratch.count)
            guard required > 0 else { return [] }
            if required <= scratch.count {
                return Array(UnsafeBufferPointer(start: scratch.baseAddress, count: required))
            }
            return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: required) { large -> [UInt8] in
                let written = write(large.baseAddress, large.count)
                guard written == required else { return [] }
                return Array(UnsafeBufferPointer(start: large.baseAddress, count: written))
            }
        }
    }

    private func readString(_ write: (UnsafeMutablePointer<UInt8>?, Int) -> Int) -> String {
        String(decoding: readBytes(write), as: UTF8.self)
    }

    /// Reads a packed string list — `[u32 count]` then `count` × `[u32 len][bytes]`,
    /// little-endian, no delimiter — so a candidate may contain any byte (even a
    /// newline) and an empty string round-trips faithfully.
    private func readStringList(_ write: (UnsafeMutablePointer<UInt8>?, Int) -> Int) -> [String] {
        parseStringList(readBytes(write))
    }

    private func parseStringList(_ bytes: [UInt8]) -> [String] {
        guard bytes.count >= 4 else { return [] }
        func readUInt32(at offset: Int) -> Int {
            Int(UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24)
        }

        let count = readUInt32(at: 0)
        var offset = 4
        var items: [String] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            guard offset + 4 <= bytes.count else { break }
            let length = readUInt32(at: offset)
            offset += 4
            guard offset + length <= bytes.count else { break }
            items.append(String(decoding: bytes[offset..<offset + length], as: UTF8.self))
            offset += length
        }
        return items
    }
}
