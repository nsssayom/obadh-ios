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
    @State private var step: Step
    @State private var isRevealed = false

    init(install: KeyboardInstallState, onFinish: @escaping () -> Void) {
        self.install = install
        self.onFinish = onFinish
        _step = State(initialValue: Self.initialStep)
    }

    /// Onboarding can't be driven without a mouse, so Debug builds can jump straight to
    /// a step for screenshots: `--onboarding-step=fullAccess`. Compiled out of Release.
    private static var initialStep: Step {
        #if DEBUG
        let prefix = "--onboarding-step="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            switch argument.dropFirst(prefix.count) {
            case "addKeyboard": return .addKeyboard
            case "fullAccess": return .fullAccess
            case "done": return .done
            default: break
            }
        }
        #endif
        return .welcome
    }

    var body: some View {
        ZStack {
            BrandBackground()

            content
                // Pad first, then fill. The other order expands the content to the full
                // width and *then* insets the result, pushing text off both edges.
                .padding(.horizontal, 30)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
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
                    Text("Or find it in General › Keyboard › Keyboards.")
                        .font(BrandFont.caption)
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

            // "Not now" already says this is optional, and the privacy story belongs on
            // the Privacy screen, not in a permission prompt.
            message("Full Access lets Obadh vibrate as you type.")
                .padding(.top, 14)

            if install.isFullAccessConfirmed {
                confirmation("Full Access is on")
                    .padding(.top, 24)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            halo("checkmark.seal.fill", tint: .green)

            title("You're all set")
                .padding(.top, 28)

            message("Tap the globe key to switch to Obadh.")
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
            .font(BrandFont.title)
            .tracking(-0.4)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.body)
            .foregroundStyle(.secondary)
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
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(BrandGradient.action, in: Circle())
            Text(text)
                .font(BrandFont.body)
        }
    }

    private func confirmation(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.green)
            .transition(.scale.combined(with: .opacity))
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(BrandButtonStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(BrandFont.body)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
    }
}
