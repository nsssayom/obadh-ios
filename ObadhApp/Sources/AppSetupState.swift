import Foundation
import UIKit

/// First-run state. App-local, so it lives in the app's own defaults rather than the
/// shared container — the keyboard has no use for it, and the shared container is
/// unreachable from the extension without Full Access anyway.
enum AppSetupState {
    static let hasCompletedOnboardingKey = "app.hasCompletedOnboarding"
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
