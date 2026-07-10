import SwiftUI

/// First-run setup. Three questions, asked once: do you want it, is it added, do you
/// want haptics. Nothing here is ever shown again.
struct OnboardingView: View {
    private enum Step {
        case welcome
        case addKeyboard
        case fullAccess
        case done
    }

    let install: KeyboardInstallState
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var step: Step = .welcome
    @State private var isRevealed = false

    var body: some View {
        ZStack {
            BrandBackground()

            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                // Recreating on `step` is what drives the transition below.
                .id(step)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 18)),
                        removal: .opacity.combined(with: .offset(y: -14))
                    )
                )
        }
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, 30)
                .padding(.bottom, 14)
                .reveal(5, isVisible: isRevealed)
        }
        .onAppear { isRevealed = true }
        .onChange(of: install) { _, state in
            // The user just came back from Settings having added it. Let the check mark
            // land before moving on, so the confirmation is seen rather than inferred.
            guard step == .addKeyboard, state.isKeyboardInstalled else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                advance(to: .fullAccess)
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .addKeyboard: addKeyboard
        case .fullAccess: fullAccess
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            BrandMark()
                .reveal(0, isVisible: isRevealed)

            Text("Obadh")
                .font(BrandFont.wordmark(58))
                .tracking(-0.5)
                .foregroundStyle(BrandGradient.wordmark(scheme))
                .padding(.top, 34)
                .reveal(1, isVisible: isRevealed)

            Text("ভাষা হোক আরও উন্মুক্ত")
                .font(BrandFont.bangla(21))
                .foregroundStyle(scheme == .dark ? Color.obadhTealLight : Color.obadhDeep)
                .opacity(0.9)
                .padding(.top, 10)
                .reveal(2, isVisible: isRevealed)
        }
    }

    private var addKeyboard: some View {
        VStack(spacing: 0) {
            halo("keyboard")

            title("Add Obadh to\nyour keyboards")
                .padding(.top, 28)

            card {
                numberedStep(1, "Open Settings")
                numberedStep(2, "Tap Keyboards")
                numberedStep(3, "Turn on Obadh")
            }
            .padding(.top, 28)

            Group {
                if install.isKeyboardInstalled {
                    confirmation("Obadh is added")
                } else {
                    Text("Not seeing Keyboards there? Settings › General › Keyboard › Keyboards › Add New Keyboard.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 22)
        }
    }

    private var fullAccess: some View {
        VStack(spacing: 0) {
            halo("hand.tap.fill")

            title("Turn on haptics?")
                .padding(.top, 28)

            Text("Obadh works completely without this.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text("Full Access lets the keyboard vibrate as you type, and lets the settings in this app reach it.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Group {
                if install.isFullAccessConfirmed {
                    confirmation("Full Access is on")
                } else {
                    Label("Nothing you type ever leaves your device", systemImage: "lock.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(scheme == .dark ? Color.obadhTealLight : Color.obadhDeep)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.top, 26)
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            halo("checkmark.seal.fill", tint: .green)

            title("You're all set")
                .padding(.top, 28)

            Text("Tap the globe key in any app to switch to Obadh.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 6) {
            switch step {
            case .welcome:
                primaryButton("Get Started") {
                    advance(to: install.isKeyboardInstalled ? .fullAccess : .addKeyboard)
                }

            case .addKeyboard:
                if install.isKeyboardInstalled {
                    primaryButton("Continue") { advance(to: .fullAccess) }
                } else {
                    primaryButton("Open Settings", action: openSystemSettings)
                }

            case .fullAccess:
                if install.isFullAccessConfirmed {
                    primaryButton("Continue") { advance(to: .done) }
                } else {
                    primaryButton("Open Settings", action: openSystemSettings)
                    secondaryButton("Not now") { advance(to: .done) }
                }

            case .done:
                primaryButton("Done", action: onFinish)
            }
        }
    }

    private func advance(to next: Step) {
        withAnimation(.smooth(duration: 0.45)) { step = next }
    }

    // MARK: - Pieces

    private func halo(_ symbol: String, tint: Color = .obadhTeal) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 46, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(scheme == .dark ? tint : Color.obadhDeep)
            .frame(width: 112, height: 112)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(tint.opacity(0.25), lineWidth: 1))
            )
            .shadow(color: tint.opacity(0.22), radius: 24, y: 8)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 32, weight: .semibold))
            .tracking(-0.5)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card(@ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obadhTeal.opacity(0.18), lineWidth: 1)
        )
    }

    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(BrandGradient.action, in: Circle())
            Text(text)
                .font(.body)
        }
    }

    private func confirmation(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.green)
            .transition(.scale.combined(with: .opacity))
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(BrandButtonStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
    }
}
