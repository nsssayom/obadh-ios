import Foundation

struct KeyboardPreferences {
    static let appGroupIdentifier = "group.com.nsssayom.obadh"
    private static let hapticFeedbackEnabledKey = "keyboard.hapticFeedbackEnabled"

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

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
