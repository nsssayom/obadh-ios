import SwiftUI
import UIKit

/// The app after setup: preferences, and nothing else. Setup guidance reappears only
/// when the keyboard is actually missing.
struct SettingsView: View {
    let install: KeyboardInstallState

    private let preferences = KeyboardPreferences()
    private let hapticPreview = UISelectionFeedbackGenerator()

    @State private var hapticFeedbackEnabled: Bool
    @State private var emojiSearchLanguage: EmojiSearchLanguage

    init(install: KeyboardInstallState) {
        self.install = install
        let preferences = KeyboardPreferences()
        _hapticFeedbackEnabled = State(initialValue: preferences.hapticFeedbackEnabled)
        _emojiSearchLanguage = State(initialValue: preferences.defaultEmojiSearchLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !install.isKeyboardInstalled {
                    keyboardMissingSection
                }
                keyboardSection
                emojiSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Obadh")
        }
    }

    /// The only nag in the app, and it is load-bearing: without this the keyboard is
    /// simply gone and nothing else on this screen means anything.
    private var keyboardMissingSection: some View {
        Section {
            Button(action: openSystemSettings) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Obadh isn't in your keyboards")
                            .foregroundStyle(.primary)
                        Text("Open Settings › Keyboards to add it")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
                .onChange(of: hapticFeedbackEnabled) { _, enabled in
                    preferences.hapticFeedbackEnabled = enabled
                    guard enabled else { return }
                    hapticPreview.prepare()
                    hapticPreview.selectionChanged()
                }
        } header: {
            Text("Keyboard")
        } footer: {
            // Shown only while unconfirmed. Once the keyboard has run with Full Access
            // this never comes back — and we never claim Full Access is *off*, because
            // absence of the stamp does not prove that.
            if !install.isFullAccessConfirmed {
                Button(action: openSystemSettings) {
                    Text("Haptics need Full Access, which Obadh doesn't have yet. Turn it on in Settings › Keyboards.")
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emojiSection: some View {
        Section("Emoji") {
            Picker("Search Language", selection: $emojiSearchLanguage) {
                Text("English").tag(EmojiSearchLanguage.english)
                Text("বাংলা").tag(EmojiSearchLanguage.bangla)
            }
            .onChange(of: emojiSearchLanguage) { _, language in
                preferences.defaultEmojiSearchLanguage = language
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            NavigationLink("Privacy") { PrivacyView() }
            // The full build stamp lives behind this row, not under it.
            NavigationLink {
                AboutView()
            } label: {
                LabeledContent(
                    "Version",
                    value: "\(AppBuildInfo.shortVersion) (\(AppBuildInfo.buildNumber))"
                )
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            NavigationLink("Keyboard Test Field") {
                KeyboardTestScreen()
                    .navigationBarTitleDisplayMode(.inline)
                    .ignoresSafeArea(.keyboard)
            }
        }
    }
    #endif
}
