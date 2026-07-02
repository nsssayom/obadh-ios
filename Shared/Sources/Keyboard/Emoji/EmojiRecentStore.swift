import Foundation

struct EmojiRecentStore {
    private static let key = "keyboard.emoji.recents"
    private static let limit = 64
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardPreferences.sharedDefaults) {
        self.defaults = defaults
    }

    func load() -> [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ emoji: String) {
        var values = load().filter { $0 != emoji }
        values.insert(emoji, at: 0)
        if values.count > Self.limit {
            values.removeLast(values.count - Self.limit)
        }
        defaults.set(values, forKey: Self.key)
    }
}
