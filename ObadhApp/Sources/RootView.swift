import SwiftUI

struct RootView: View {
    @AppStorage(AppSetupState.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var install = KeyboardInstallStateReader().read()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                SettingsView(install: install)
            } else {
                OnboardingView(install: install) {
                    withAnimation(.snappy) { hasCompletedOnboarding = true }
                }
            }
        }
        // Both signals only change while the user is away in Settings, so a foreground
        // re-read is the whole of the refresh story. No polling, no observers.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            withAnimation(.snappy) { install = KeyboardInstallStateReader().read() }
        }
    }
}
