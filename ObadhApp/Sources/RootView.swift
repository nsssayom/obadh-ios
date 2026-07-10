import Combine
import SwiftUI
import UIKit

struct RootView: View {
    @AppStorage(AppSetupState.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @State private var install = KeyboardInstallStateReader().read()

    /// `@Environment(\.scenePhase)` is supplied by SwiftUI's own App/Scene lifecycle. This
    /// app is UIKit hosting SwiftUI in a UIHostingController, so it never updates here —
    /// the foreground re-read silently never ran. UIKit's own notification does fire.
    private let didBecomeActive = NotificationCenter.default
        .publisher(for: UIApplication.didBecomeActiveNotification)

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                SettingsView(install: install)
            } else {
                OnboardingView(install: install) {
                    AppSetupState.clearOnboardingProgress()
                    withAnimation(.snappy) { hasCompletedOnboarding = true }
                }
            }
        }
        // Both signals only change while the user is away in Settings, so a foreground
        // re-read is the whole of the refresh story. No polling.
        .onReceive(didBecomeActive) { _ in
            withAnimation(.snappy) { install = KeyboardInstallStateReader().read() }
        }
    }
}
