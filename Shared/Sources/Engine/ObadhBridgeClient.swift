import Foundation
import ObadhBridge

struct ObadhModelConfiguration: Equatable {
    let autocorrectAvailable: Bool
    let autosuggestAvailable: Bool
}

struct ObadhBridgeClient: BanglaTypingEngine, Sendable {
    static let shared = ObadhBridgeClient()

    private init() {}

    func configureModels(in bundle: Bundle) -> ObadhModelConfiguration {
        let autocorrectAvailable = configureAutocorrect(in: bundle)
        let autosuggestAvailable = configureAutosuggest(in: bundle)
        return ObadhModelConfiguration(
            autocorrectAvailable: autocorrectAvailable,
            autosuggestAvailable: autosuggestAvailable
        )
    }

    func transliterate(_ input: String) -> String {
        callBridge(input, obadh_transliterate_utf8)
    }

    func transliterateLenient(_ input: String) -> String {
        callBridge(input, obadh_transliterate_lenient_utf8)
    }

    func compositionSuggestions(for romanInput: String, limit: Int) -> [String] {
        callBridgeList(romanInput, limit: limit, obadh_composition_suggestions_utf8)
    }

    /// Whether `word` is an exact entry in the autocorrect lexicon (`bn.fst`). The gate
    /// for auto-applying a correction: a real word is never second-guessed.
    func isLexiconWord(_ word: String) -> Bool {
        var word = word
        return word.withUTF8 { buffer in
            obadh_is_lexicon_word_utf8(buffer.baseAddress, buffer.count) == 1
        }
    }

    func autosuggestSuggestions(for context: String, limit: Int) -> [String] {
        callBridgeList(context, limit: limit, obadh_autosuggest_suggestions_utf8)
    }

    func autosuggestSessionSuggestions(limit: Int) -> [String] {
        callBridgeListWithoutInput(limit: limit, obadh_autosuggest_session_suggestions_utf8)
    }

    @discardableResult
    func commitAutosuggestToken(_ token: String) -> Bool {
        let tokenBytes = Array(token.utf8)
        return tokenBytes.withUnsafeBufferPointer { tokenBuffer in
            obadh_autosuggest_commit_token_utf8(tokenBuffer.baseAddress, tokenBuffer.count)
        }
    }

    func clearAutosuggestSession() {
        obadh_autosuggest_clear_session()
    }

    func clearPersonalAutosuggest() {
        obadh_autosuggest_clear_personal()
    }

    func personalAutosuggestSnapshotLength() -> Int {
        obadh_autosuggest_personal_snapshot_len()
    }

    func exportPersonalAutosuggestSnapshot() -> Data? {
        let requiredLength = obadh_autosuggest_export_personal_snapshot(nil, 0)
        guard requiredLength > 0 else {
            return nil
        }

        var data = Data(count: requiredLength)
        let written = data.withUnsafeMutableBytes { outputBuffer in
            obadh_autosuggest_export_personal_snapshot(
                outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                outputBuffer.count
            )
        }
        guard written == requiredLength else {
            return nil
        }
        return data
    }

    func importPersonalAutosuggestSnapshot(_ data: Data) -> Bool {
        guard !data.isEmpty else {
            return false
        }
        return data.withUnsafeBytes { inputBuffer in
            obadh_autosuggest_import_personal_snapshot(
                inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                inputBuffer.count
            )
        }
    }

    private func configureAutocorrect(in bundle: Bundle) -> Bool {
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
            return false
        }

        let fstPath = Array(fstURL.path.utf8)
        let loanwordPath = Array(loanwordURL.path.utf8)
        return fstPath.withUnsafeBufferPointer { fstBuffer in
            loanwordPath.withUnsafeBufferPointer { loanwordBuffer in
                obadh_configure_autocorrect_utf8(
                    fstBuffer.baseAddress,
                    fstBuffer.count,
                    loanwordBuffer.baseAddress,
                    loanwordBuffer.count
                )
            }
        }
    }

    private func configureAutosuggest(in bundle: Bundle) -> Bool {
        guard
            let artifactURL = bundle.url(
                forResource: "autosuggest-ngram-c64",
                withExtension: "bin",
                subdirectory: "ObadhModels/autosuggest"
            )
        else {
            return false
        }

        let artifactPath = Array(artifactURL.path.utf8)
        return artifactPath.withUnsafeBufferPointer { artifactBuffer in
            obadh_configure_autosuggest_utf8(artifactBuffer.baseAddress, artifactBuffer.count)
        }
    }

    /// Words and suggestion lists are short, so a stack scratch buffer usually
    /// satisfies the whole call in a single crossing with zero heap allocation.
    private static let scratchCapacity = 1024

    private func callBridge(
        _ input: String,
        _ function: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UInt8>?, Int) -> Int
    ) -> String {
        var input = input
        return input.withUTF8 { inputBuffer in
            readUTF8 { outputPtr, outputCapacity in
                function(inputBuffer.baseAddress, inputBuffer.count, outputPtr, outputCapacity)
            }
        }
    }

    private func callBridgeList(
        _ input: String,
        limit: Int,
        _ function: (UnsafePointer<UInt8>?, Int, Int, UnsafeMutablePointer<UInt8>?, Int) -> Int
    ) -> [String] {
        let boundedLimit = max(0, limit)
        var input = input
        let joined = input.withUTF8 { inputBuffer in
            readUTF8 { outputPtr, outputCapacity in
                function(inputBuffer.baseAddress, inputBuffer.count, boundedLimit, outputPtr, outputCapacity)
            }
        }
        return splitList(joined)
    }

    private func callBridgeListWithoutInput(
        limit: Int,
        _ function: (Int, UnsafeMutablePointer<UInt8>?, Int) -> Int
    ) -> [String] {
        let boundedLimit = max(0, limit)
        let joined = readUTF8 { outputPtr, outputCapacity in
            function(boundedLimit, outputPtr, outputCapacity)
        }
        return splitList(joined)
    }

    /// Invokes a size-reporting C writer into a stack buffer, growing once only
    /// if the output does not fit. The Rust side returns the required length and
    /// copies only when capacity is sufficient, so this is a single crossing in
    /// the common case.
    private func readUTF8(_ write: (UnsafeMutablePointer<UInt8>?, Int) -> Int) -> String {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Self.scratchCapacity) { scratch -> String in
            let required = write(scratch.baseAddress, scratch.count)
            guard required > 0 else { return "" }
            if required <= scratch.count {
                return String(decoding: UnsafeBufferPointer(start: scratch.baseAddress, count: required), as: UTF8.self)
            }
            return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: required) { large -> String in
                let written = write(large.baseAddress, large.count)
                guard written == required else { return "" }
                return String(decoding: UnsafeBufferPointer(start: large.baseAddress, count: written), as: UTF8.self)
            }
        }
    }

    private func splitList(_ joined: String) -> [String] {
        guard !joined.isEmpty else { return [] }
        return joined
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
