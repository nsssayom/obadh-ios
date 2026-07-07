import Foundation

/// Which keyword language the emoji-panel search runs in. English is the default;
/// the Bangla index loads lazily only when this is `.bangla`.
enum EmojiSearchLanguage: String {
    case english
    case bangla

    var toggled: EmojiSearchLanguage { self == .english ? .bangla : .english }
    /// Short label for the in-search toggle button.
    var shortLabel: String { self == .english ? "EN" : "বাং" }
}

struct KeyboardPreferences {
    static let appGroupIdentifier = "group.com.nsssayom.obadh"
    private static let hapticFeedbackEnabledKey = "keyboard.hapticFeedbackEnabled"
    private static let emojiSearchLanguageKey = "keyboard.emojiSearchLanguage"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardPreferences.sharedDefaults) {
        self.defaults = defaults
    }

    var hapticFeedbackEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.hapticFeedbackEnabledKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.hapticFeedbackEnabledKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.hapticFeedbackEnabledKey)
        }
    }

    /// Default language the emoji search opens in (set in the Obadh app). The
    /// in-search EN⇄BN toggle overrides it for the current session.
    var defaultEmojiSearchLanguage: EmojiSearchLanguage {
        get {
            EmojiSearchLanguage(rawValue: defaults.string(forKey: Self.emojiSearchLanguageKey) ?? "")
                ?? .english
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.emojiSearchLanguageKey)
        }
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    #if DEBUG
    // DEBUG-only live haptic tuning: the container app writes these from on-screen
    // sliders and the keyboard extension reads them per keystroke, so haptic feel
    // can be dialed in on real hardware without rebuilds. Compile-excluded from
    // Release. Defaults mirror the shipped letter tick (intensity 0.8/sharpness
    // 0.75). See KeyboardFeedbackController + KeyboardTestViewController.
    private static let debugHapticOverrideKey = "debug.hapticOverrideEnabled"
    private static let debugHapticIntensityKey = "debug.hapticIntensity"
    private static let debugHapticSharpnessKey = "debug.hapticSharpness"

    var debugHapticOverrideEnabled: Bool {
        get { defaults.bool(forKey: Self.debugHapticOverrideKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.debugHapticOverrideKey) }
    }

    var debugHapticIntensity: Double {
        get { defaults.object(forKey: Self.debugHapticIntensityKey) as? Double ?? 0.5 }
        nonmutating set { defaults.set(newValue, forKey: Self.debugHapticIntensityKey) }
    }

    var debugHapticSharpness: Double {
        get { defaults.object(forKey: Self.debugHapticSharpnessKey) as? Double ?? 0.9 }
        nonmutating set { defaults.set(newValue, forKey: Self.debugHapticSharpnessKey) }
    }
    #endif
}
