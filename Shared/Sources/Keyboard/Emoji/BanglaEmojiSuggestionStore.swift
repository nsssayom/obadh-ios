import Foundation

/// Supplies a single high-confidence emoji for a fully-composed Bangla word, for
/// the inline "type-as-you-go" suggestion. Kept separate from `BanglaTypingEngine`
/// so the composer can be tested with a fixture.
protocol BanglaEmojiSuggesting {
    /// Up to 3 high-confidence emoji for an exact (normalized) Bangla word, best
    /// first (mirroring the native keyboard, which shows up to 3). Empty when
    /// there's no confident match. Exact match only — never fuzzy — so nothing
    /// weak surfaces.
    func emojis(for banglaWord: String) -> [String]
}

/// Reads the compiled `emoji-bn.bin` (`OBEMOJIBN1`) — a tiny, sorted-key binary
/// mapping a normalized Bangla word to one emoji — and answers exact lookups by
/// binary search over the mmap'd bytes. No allocation on a miss, so it's safe on
/// the per-keystroke path. Built by `scripts/generate-emoji-data.py`.
struct BanglaEmojiSuggestionStore: BanglaEmojiSuggesting {
    private let data: Data
    private let keyCount: Int
    private let keyRecordsOffset: Int
    private let stringBlobOffset: Int

    static let empty = BanglaEmojiSuggestionStore(
        data: Data(), keyCount: 0, keyRecordsOffset: 0, stringBlobOffset: 0
    )

    private init(data: Data, keyCount: Int, keyRecordsOffset: Int, stringBlobOffset: Int) {
        self.data = data
        self.keyCount = keyCount
        self.keyRecordsOffset = keyRecordsOffset
        self.stringBlobOffset = stringBlobOffset
    }

    init(bundle: Bundle) {
        if let url = bundle.url(
            forResource: "emoji-bn",
            withExtension: "bin",
            subdirectory: "ObadhModels/emoji"
        ),
           let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
           let store = Self.decode(data) {
            self = store
        } else {
            self = .empty
        }
    }

    init?(data: Data) {
        guard let store = Self.decode(data) else { return nil }
        self = store
    }

    func emojis(for banglaWord: String) -> [String] {
        guard keyCount > 0 else { return [] }
        let key = Self.normalize(banglaWord)
        guard !key.isEmpty else { return [] }
        let needle = Array(key.utf8)

        return data.withUnsafeBytes { bytes -> [String] in
            var low = 0
            var high = keyCount - 1
            while low <= high {
                let mid = (low + high) / 2
                let record = keyRecordsOffset + mid * 8
                let keyOffset = stringBlobOffset + Int(Self.readUInt32(bytes, record))
                let comparison = Self.compareCString(bytes, at: keyOffset, with: needle)
                if comparison == 0 {
                    // Value is up to 3 emoji joined by U+001F (unit separator).
                    let listOffset = stringBlobOffset + Int(Self.readUInt32(bytes, record + 4))
                    guard let list = Self.readCString(bytes, at: listOffset) else { return [] }
                    return list.split(separator: "\u{1f}").map(String.init)
                } else if comparison < 0 {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return []
        }
    }

    /// Must stay byte-for-byte identical to `normalize_bangla` in the generator so
    /// the composed word matches the interned key: NFC, strip ZWNJ/ZWJ, trim.
    /// (Do NOT strip combining marks — Bangla matras are essential.)
    static func normalize(_ value: String) -> String {
        let composed = value.precomposedStringWithCanonicalMapping
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(composed.unicodeScalars.count)
        for scalar in composed.unicodeScalars where scalar != "\u{200c}" && scalar != "\u{200d}" {
            scalars.append(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Binary decoding

    private static func decode(_ data: Data) -> BanglaEmojiSuggestionStore? {
        data.withUnsafeBytes { bytes -> BanglaEmojiSuggestionStore? in
            let magic = Array("OBEMOJIBN1".utf8)
            guard bytes.count >= 30 else { return nil }
            for index in magic.indices where bytes[index] != magic[index] {
                return nil
            }
            guard readUInt16(bytes, 10) == 1 else { return nil }
            let keyCount = Int(readUInt32(bytes, 14))
            let keyRecordsOffset = Int(readUInt32(bytes, 18))
            let stringBlobOffset = Int(readUInt32(bytes, 22))
            let stringBlobSize = Int(readUInt32(bytes, 26))
            guard
                keyCount >= 0,
                keyRecordsOffset >= 30,
                keyRecordsOffset + keyCount * 8 <= bytes.count,
                stringBlobOffset >= 0,
                stringBlobSize >= 0,
                stringBlobOffset + stringBlobSize <= bytes.count
            else {
                return nil
            }
            return BanglaEmojiSuggestionStore(
                data: data,
                keyCount: keyCount,
                keyRecordsOffset: keyRecordsOffset,
                stringBlobOffset: stringBlobOffset
            )
        }
    }

    /// Compares the NUL-terminated key at `offset` with `needle` (no NUL).
    /// Returns <0 if key < needle, 0 if equal, >0 if key > needle.
    private static func compareCString(
        _ bytes: UnsafeRawBufferPointer,
        at offset: Int,
        with needle: [UInt8]
    ) -> Int {
        var index = 0
        while true {
            let keyByte = offset + index < bytes.count ? bytes[offset + index] : 0
            let needleEnded = index >= needle.count
            if keyByte == 0 && needleEnded { return 0 }
            if keyByte == 0 { return -1 }
            if needleEnded { return 1 }
            if keyByte != needle[index] {
                return keyByte < needle[index] ? -1 : 1
            }
            index += 1
        }
    }

    private static func readCString(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> String? {
        guard offset >= 0, offset < bytes.count else { return nil }
        var end = offset
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        return String(decoding: bytes[offset..<end], as: UTF8.self)
    }

    private static func readUInt16(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
        UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }

    private static func readUInt32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
