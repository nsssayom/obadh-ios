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
    case space
    case returnKey

    var weight: Double {
        switch self {
        case .space:
            5.0
        case .returnKey:
            2.25
        case .modeSwitch, .emoji:
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
    static let danda = Self.terminator("\u{0964}")
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

    static func rows(for mode: KeyboardMode) -> [KeyboardRow] {
        switch mode {
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
                KeyboardRow(
                    keys: [.modeSwitch("123"), .emoji, .space, .returnKey],
                    keyWeights: NativeGeometry.commandRowWeights
                )
            ]
        case .numbers:
            [
                KeyboardRow(keys: ["১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০"].map { .symbol(.literal($0)) }),
                KeyboardRow(
                    keys: ["-", "/", ":", ";", "(", ")", "৳", "'", "@", "\""].map { .symbol(.literal($0)) }
                ),
                KeyboardRow(
                    keys: [.modeSwitch("#+=")]
                        + [.symbol(.danda), .symbol(.literal(".")), .symbol(.literal(","))]
                        + [.symbol(.terminator("?")), .symbol(.terminator("!"))]
                        + [.backspace],
                    keyWeights: NativeGeometry.punctuationLowerRowWeights,
                    customSpacingAfterKeyIndex: NativeGeometry.punctuationLowerRowSpacingAfterKeyIndex
                ),
                KeyboardRow(
                    keys: [.modeSwitch("ABC"), .space, .returnKey],
                    keyWeights: NativeGeometry.punctuationCommandRowWeights
                )
            ]
        case .symbols:
            [
                KeyboardRow(keys: ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { .symbol(.literal($0)) }),
                KeyboardRow(
                    keys: ["_", "\\", "|", "~", "<", ">", "&", "$", "€", "£"].map { .symbol(.literal($0)) }
                ),
                KeyboardRow(
                    keys: [.modeSwitch("123")]
                        + [.symbol(.danda), .symbol(.literal(".")), .symbol(.literal(","))]
                        + [.symbol(.terminator("?")), .symbol(.terminator("!"))]
                        + [.backspace],
                    keyWeights: NativeGeometry.punctuationLowerRowWeights,
                    customSpacingAfterKeyIndex: NativeGeometry.punctuationLowerRowSpacingAfterKeyIndex
                ),
                KeyboardRow(
                    keys: [.modeSwitch("ABC"), .space, .returnKey],
                    keyWeights: NativeGeometry.punctuationCommandRowWeights
                )
            ]
        }
    }
}
