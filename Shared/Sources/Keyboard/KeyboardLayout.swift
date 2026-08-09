import Foundation

enum KeyboardMode: Equatable {
    case letters
    case numbers
    case symbols
}

enum KeyboardKey: Equatable {
    case character(String)
    case symbol(KeyboardSymbol)
    case shift
    case backspace
    case modeSwitch(String)
    case emoji
    /// Next-keyboard switch. Only laid out when the system does NOT provide its
    /// own (see `needsInputModeSwitchKey`): on iPhone the system draws a globe in
    /// the row below our view, but on iPad it does not, which left no way out of
    /// Obadh at all.
    case globe
    /// iPad-only keys, mirroring the native iPad key set. iPhone never lays these
    /// out, so its rows are untouched.
    case tab
    case capsLock
    case hideKeyboard
    case space
    case returnKey

    var weight: Double {
        switch self {
        case .space:
            5.0
        case .returnKey:
            2.25
        case .modeSwitch, .emoji, .globe, .tab, .capsLock, .hideKeyboard:
            1.25
        case .shift, .backspace:
            1.35
        case .character, .symbol:
            1
        }
    }
}

struct KeyboardSymbol: Equatable {
    let label: String
    let output: String
    let role: Role

    enum Role: Equatable {
        case literal
        case sentenceTerminator
    }

    static func literal(_ value: String, output: String? = nil) -> Self {
        Self(label: value, output: output ?? value, role: .literal)
    }

    /// A sentence-ending symbol: it commits any active composition and marks an
    /// autosuggest boundary. Used for দাঁড়ি `।`, `?`, and `!`.
    static func terminator(_ value: String, output: String? = nil) -> Self {
        Self(label: value, output: output ?? value, role: .sentenceTerminator)
    }

    /// দাঁড়ি — the Bangla full stop.
    static let dari = Self.terminator("\u{0964}")
}

struct KeyboardRow: Equatable {
    let keys: [KeyboardKey]
    let keyWeights: [Double]?
    let customSpacingAfterKeyIndex: [Int: Double]
    let leadingFlex: Double
    let trailingFlex: Double

    init(
        keys: [KeyboardKey],
        keyWeights: [Double]? = nil,
        customSpacingAfterKeyIndex: [Int: Double] = [:],
        leadingFlex: Double = 0,
        trailingFlex: Double = 0
    ) {
        assert(keyWeights == nil || keyWeights?.count == keys.count)
        self.keys = keys
        self.keyWeights = keyWeights?.count == keys.count ? keyWeights : nil
        self.customSpacingAfterKeyIndex = customSpacingAfterKeyIndex
        self.leadingFlex = leadingFlex
        self.trailingFlex = trailingFlex
    }
}

enum KeyboardLayoutProvider {
    private enum NativeGeometry {
        // iOS 26 phone portrait measurements from native keyboard screenshots
        // on a 440 pt-wide device class.
        static let standardKeyWidth = 37.33
        static let keyboardSideInset = 6.67
        static let homeRowScreenIndent = 28.0
        static let homeRowInternalIndent = homeRowScreenIndent - keyboardSideInset
        static let commandKeyWidth = 48.0
        static let spaceKeyWidth = 210.67
        static let returnKeyWidth = 102.33
        static let edgeCommandKeyWidth = 50.33
        static let edgeBackspaceKeyWidth = 50.33
        static let rowThreeSideGap = 14.67
        static let punctuationSymbolKeyWidth = 54.53
        static let commandRowWeights = [
            commandKeyWidth,
            commandKeyWidth,
            spaceKeyWidth,
            returnKeyWidth
        ]
        static let punctuationCommandRowWeights = [
            returnKeyWidth,
            spaceKeyWidth,
            returnKeyWidth
        ]

        static let lowerRowWeights = [edgeCommandKeyWidth / standardKeyWidth]
            + Array(repeating: 1.0, count: 7)
            + [edgeBackspaceKeyWidth / standardKeyWidth]

        static let lowerRowSpacingAfterKeyIndex = [
            0: rowThreeSideGap,
            7: rowThreeSideGap
        ]

        static let punctuationLowerRowWeights = [edgeCommandKeyWidth]
            + Array(repeating: punctuationSymbolKeyWidth, count: 5)
            + [edgeBackspaceKeyWidth]

        static let punctuationLowerRowSpacingAfterKeyIndex = [
            0: rowThreeSideGap,
            5: rowThreeSideGap
        ]
    }


    /// The bottom command row. When the system does not supply a next-keyboard key
    /// we add our own (see `KeyboardKey.globe`). No explicit weights: each key's own
    /// `weight` applies, so space keeps its 5.0 share and the row re-proportions
    /// itself around the extra key instead of being hand-tuned per variant.
    private static func commandRow(leading: [KeyboardKey], includesGlobeKey: Bool) -> KeyboardRow {
        KeyboardRow(keys: leading + (includesGlobeKey ? [.globe] : []) + [.space, .returnKey])
    }

    /// Native iPad key widths, measured on an iPad Pro 11-inch (M4) portrait
    /// (834pt) and expressed as multiples of the 56.3pt standard key, so they hold
    /// at any iPad width: tab/backspace 72.6, caps 92.6, return 118.6, left shift
    /// 121.6, right shift 89.0, and a bottom row of 59.3/59.9/59.9/409.2/88.4/89.0.
    private enum PadGeometry {
        static let standard: Double = 56.3
        static let row1 = [72.6 / standard] + Array(repeating: 1.0, count: 10) + [72.6 / standard]
        static let row2 = [92.6 / standard] + Array(repeating: 1.0, count: 9) + [118.6 / standard]
        static let row3 = [121.6 / standard] + Array(repeating: 1.0, count: 9) + [89.0 / standard]
        static let row4 = [59.3, 59.9, 59.9, 409.2, 88.4, 89.0].map { $0 / standard }
    }

    /// The native iPad set: a tab and caps key, punctuation on the lower row, shift
    /// on BOTH sides, and a bottom row of emoji / .?123 / globe / space / .?123 /
    /// hide-keyboard. Native puts dictation where the globe sits here; we have no
    /// dictation, and the globe has to live somewhere the system does not provide it.
    private static func padRows(for mode: KeyboardMode) -> [KeyboardRow] {
        let bottom = KeyboardRow(
            keys: [.emoji, .modeSwitch(mode == .letters ? "123" : "ABC"), .globe, .space,
                   .modeSwitch(mode == .letters ? "123" : "ABC"), .hideKeyboard],
            keyWeights: PadGeometry.row4
        )
        switch mode {
        case .letters:
            return [
                KeyboardRow(keys: [.tab] + "qwertyuiop".map { .character(String($0)) } + [.backspace],
                            keyWeights: PadGeometry.row1),
                KeyboardRow(keys: [.capsLock] + "asdfghjkl".map { .character(String($0)) } + [.returnKey],
                            keyWeights: PadGeometry.row2),
                KeyboardRow(keys: [.shift] + "zxcvbnm".map { .character(String($0)) }
                                + [.symbol(.terminator("!")), .symbol(.terminator("?")), .shift],
                            keyWeights: PadGeometry.row3),
                bottom
            ]
        case .numbers, .symbols:
            let top = mode == .numbers
                ? ["১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০"]
                : ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
            let middle = mode == .numbers
                ? ["-", "/", ":", ";", "(", ")", "৳", "&", "@"]
                : ["_", "\\", "|", "~", "<", ">", "€", "£", "¥"]
            return [
                KeyboardRow(keys: [.tab] + top.map { .symbol(.literal($0)) } + [.backspace],
                            keyWeights: PadGeometry.row1),
                KeyboardRow(keys: [.capsLock] + middle.map { .symbol(.literal($0)) } + [.returnKey],
                            keyWeights: PadGeometry.row2),
                KeyboardRow(keys: [.modeSwitch(mode == .numbers ? "#+=" : "123")]
                                + [.symbol(.dari), .symbol(.literal(".")), .symbol(.literal(",")),
                                   .symbol(.literal("'")), .symbol(.literal("\"")), .symbol(.literal("*")),
                                   .symbol(.terminator("!")), .symbol(.terminator("?"))]
                                + [.modeSwitch(mode == .numbers ? "#+=" : "123")],
                            keyWeights: PadGeometry.row3),
                bottom
            ]
        }
    }

    static func rows(for mode: KeyboardMode, includesGlobeKey: Bool = false, isPad: Bool = false) -> [KeyboardRow] {
        if isPad { return padRows(for: mode) }
        return switch mode {
        case .letters:
            [
                KeyboardRow(keys: "qwertyuiop".map { .character(String($0)) }),
                KeyboardRow(
                    keys: "asdfghjkl".map { .character(String($0)) },
                    leadingFlex: NativeGeometry.homeRowInternalIndent / NativeGeometry.standardKeyWidth,
                    trailingFlex: NativeGeometry.homeRowInternalIndent / NativeGeometry.standardKeyWidth
                ),
                KeyboardRow(
                    keys: [.shift] + "zxcvbnm".map { .character(String($0)) } + [.backspace],
                    keyWeights: NativeGeometry.lowerRowWeights,
                    customSpacingAfterKeyIndex: NativeGeometry.lowerRowSpacingAfterKeyIndex
                ),
                commandRow(leading: [.modeSwitch("123"), .emoji], includesGlobeKey: includesGlobeKey)
            ]
        case .numbers:
            [
                KeyboardRow(keys: ["১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০"].map { .symbol(.literal($0)) }),
                KeyboardRow(
                    keys: ["-", "/", ":", ";", "(", ")", "৳", "'", "@", "\""].map { .symbol(.literal($0)) }
                ),
                KeyboardRow(
                    keys: [.modeSwitch("#+=")]
                        + [.symbol(.dari), .symbol(.literal(".")), .symbol(.literal(","))]
                        + [.symbol(.terminator("?")), .symbol(.terminator("!"))]
                        + [.backspace],
                    keyWeights: NativeGeometry.punctuationLowerRowWeights,
                    customSpacingAfterKeyIndex: NativeGeometry.punctuationLowerRowSpacingAfterKeyIndex
                ),
                commandRow(leading: [.modeSwitch("ABC")], includesGlobeKey: includesGlobeKey)
            ]
        case .symbols:
            [
                KeyboardRow(keys: ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { .symbol(.literal($0)) }),
                KeyboardRow(
                    keys: ["_", "\\", "|", "~", "<", ">", "&", "$", "€", "£"].map { .symbol(.literal($0)) }
                ),
                KeyboardRow(
                    keys: [.modeSwitch("123")]
                        + [.symbol(.dari), .symbol(.literal(".")), .symbol(.literal(","))]
                        + [.symbol(.terminator("?")), .symbol(.terminator("!"))]
                        + [.backspace],
                    keyWeights: NativeGeometry.punctuationLowerRowWeights,
                    customSpacingAfterKeyIndex: NativeGeometry.punctuationLowerRowSpacingAfterKeyIndex
                ),
                commandRow(leading: [.modeSwitch("ABC")], includesGlobeKey: includesGlobeKey)
            ]
        }
    }
}
