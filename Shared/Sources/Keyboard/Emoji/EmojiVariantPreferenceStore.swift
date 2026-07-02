import Foundation

struct EmojiVariantPreferenceStore {
    private static let key = "keyboard.emoji.variantPreferences"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardPreferences.sharedDefaults) {
        self.defaults = defaults
    }

    func preferredEmoji(forBaseEmoji baseEmoji: String) -> String? {
        load()[baseEmoji]
    }

    func record(baseEmoji: String, selectedEmoji: String) {
        var values = load()
        if baseEmoji == selectedEmoji {
            values.removeValue(forKey: baseEmoji)
        } else {
            values[baseEmoji] = selectedEmoji
        }
        defaults.set(values, forKey: Self.key)
    }

    func load() -> [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
