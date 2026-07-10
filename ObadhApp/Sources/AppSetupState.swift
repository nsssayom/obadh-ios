import Foundation
import UIKit

/// First-run state. App-local, so it lives in the app's own defaults rather than the
/// shared container — the keyboard has no use for it, and the shared container is
/// unreachable from the extension without Full Access anyway.
enum AppSetupState {
    static let hasCompletedOnboardingKey = "app.hasCompletedOnboarding"

    /// Which onboarding step the user reached.
    ///
    /// This has to survive the process. Enabling a keyboard extension makes iOS
    /// re-register the containing app's plugins, which terminates the app — so the user
    /// walks to Settings from the setup step and comes back to a cold launch. With the
    /// step held only in `@State`, that cold launch dropped them at "Get Started" again,
    /// having already done the work.
    static let onboardingStepKey = "app.onboardingStep"

    static func clearOnboardingProgress() {
        UserDefaults.standard.removeObject(forKey: onboardingStepKey)
    }
}

extension URL {
    /// The only settings destination iOS exposes. It opens `Settings › Obadh`, which
    /// carries a Keyboards row because this app ships a keyboard extension. There is
    /// no public URL for the Keyboards pane itself; `App-Prefs:` is a private scheme
    /// and an App Store rejection.
    static var obadhSystemSettings: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}

@MainActor
func openSystemSettings() {
    guard let url = URL.obadhSystemSettings else { return }
    UIApplication.shared.open(url)
}
