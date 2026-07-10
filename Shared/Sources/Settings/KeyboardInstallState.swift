import Foundation

/// Whether Obadh is in the user's keyboard list, and whether it has ever run with
/// Full Access. Neither question has a direct API in the containing app.
struct KeyboardInstallState: Equatable {
    /// Obadh appears in the user's enabled keyboards.
    let isKeyboardInstalled: Bool
    /// The extension has run with Full Access at least once. See the caveat on
    /// `KeyboardInstallStateReader` — the negative case is not proof of denial.
    let isFullAccessConfirmed: Bool
}

/// Reads install state from the two signals iOS leaves lying around.
///
/// **Installed** comes from `AppleKeyboards` in the global preferences domain, which
/// `UserDefaults.standard`'s search list includes. It is not private API, but it is
/// undocumented, so a missing key reads as "not installed" rather than trapping.
///
/// **Full Access** is inferred, because a custom keyboard that lacks it cannot reach
/// the shared App Group container at all. The extension stamps a date there on every
/// launch where `hasFullAccess` is true, so seeing the stamp proves access was
/// granted. Not seeing it proves nothing: the keyboard may never have been used. Nor
/// can revocation be detected, since a keyboard without access cannot write to clear
/// the stamp. UI must therefore say "unconfirmed", never "off".
struct KeyboardInstallStateReader {
    static let keyboardBundleIdentifier = "com.nsssayom.obadh.keyboard"
    private static let appleKeyboardsKey = "AppleKeyboards"

    private let globalDefaults: UserDefaults
    private let preferences: KeyboardPreferences

    init(
        globalDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults = KeyboardPreferences.sharedDefaults
    ) {
        self.globalDefaults = globalDefaults
        self.preferences = KeyboardPreferences(defaults: sharedDefaults)
    }

    func read() -> KeyboardInstallState {
        KeyboardInstallState(
            isKeyboardInstalled: enabledKeyboardIdentifiers().contains(where: Self.isObadh),
            isFullAccessConfirmed: preferences.fullAccessConfirmedAt != nil
        )
    }

    private func enabledKeyboardIdentifiers() -> [String] {
        globalDefaults.array(forKey: Self.appleKeyboardsKey) as? [String] ?? []
    }

    /// System keyboards carry a suffix (`en_US@sw=QWERTY;hw=Automatic`) while custom
    /// ones appear as a bare bundle identifier. Match both shapes rather than depend
    /// on which one iOS happens to write.
    private static func isObadh(_ identifier: String) -> Bool {
        identifier == keyboardBundleIdentifier
            || identifier.hasPrefix("\(keyboardBundleIdentifier)@")
    }
}
