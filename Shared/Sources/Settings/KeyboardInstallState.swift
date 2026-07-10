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

    private let enabledKeyboardIdentifiers: () -> [String]
    private let preferences: KeyboardPreferences

    init(
        enabledKeyboardIdentifiers: @escaping () -> [String] = KeyboardInstallStateReader.systemEnabledKeyboardIdentifiers,
        sharedDefaults: UserDefaults = KeyboardPreferences.sharedDefaults
    ) {
        self.enabledKeyboardIdentifiers = enabledKeyboardIdentifiers
        self.preferences = KeyboardPreferences(defaults: sharedDefaults)
    }

    func read() -> KeyboardInstallState {
        KeyboardInstallState(
            isKeyboardInstalled: enabledKeyboardIdentifiers().contains(where: Self.isObadh),
            isFullAccessConfirmed: preferences.fullAccessConfirmedAt != nil
        )
    }

    /// Read through CoreFoundation rather than `UserDefaults.standard`.
    ///
    /// Settings edits this list in another process while we are suspended, and
    /// `UserDefaults`' in-process cache can hand back the value from launch — so the app
    /// comes back to the foreground still believing the keyboard is missing. The explicit
    /// synchronize forces the global domain to be re-read from `cfprefsd`.
    static func systemEnabledKeyboardIdentifiers() -> [String] {
        let viaDefaults = UserDefaults.standard.array(forKey: appleKeyboardsKey) as? [String] ?? []
        let viaCoreFoundation = coreFoundationEnabledKeyboardIdentifiers()
        // Union: each source keeps its own in-process cache and either may be the stale
        // one after Settings edits the list behind our back.
        return Array(Set(viaDefaults).union(viaCoreFoundation))
    }

    private static func coreFoundationEnabledKeyboardIdentifiers() -> [String] {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let anyHost = CFPreferencesCopyValue(
            appleKeyboardsKey as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String]
        if let anyHost, !anyHost.isEmpty { return anyHost }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue(appleKeyboardsKey as CFString, kCFPreferencesAnyApplication) as? [String] ?? []
    }

    /// System keyboards carry a suffix (`en_US@sw=QWERTY;hw=Automatic`) while custom
    /// ones appear as a bare bundle identifier. Match both shapes rather than depend
    /// on which one iOS happens to write.
    private static func isObadh(_ identifier: String) -> Bool {
        identifier == keyboardBundleIdentifier
            || identifier.hasPrefix("\(keyboardBundleIdentifier)@")
    }
}
