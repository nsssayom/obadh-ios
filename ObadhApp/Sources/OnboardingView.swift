import SwiftUI

/// First-run setup. Three questions, asked once: do you want it, is it added, do you
/// want haptics. Nothing here is ever shown again.
struct OnboardingView: View {
    /// One setup step, not two. `Settings › Obadh › Keyboards` enables the keyboard and
    /// Full Access on the same screen, so splitting them sent the user to the same place
    /// twice.
    private enum Step {
        case welcome
        case setup
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
            case "setup": return .setup
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
            guard step == .setup, state.isKeyboardInstalled else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                advance(to: .done)
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .setup: setup
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

    /// The numbered rows mirror what `Settings › Obadh` actually shows once the button
    /// opens it: a Keyboards row, and behind it both switches.
    private var setup: some View {
        VStack(spacing: 0) {
            title("Add Obadh to\nyour keyboards")

            // The diagram carries the instructions, so the numbered list is gone.
            SetupWalkthrough()
                .padding(.top, 26)

            VStack(spacing: 12) {
                if install.isKeyboardInstalled {
                    confirmation("Obadh is added")
                }
                // Uses Settings' own wording, "Allow Full Access", so the sentence and the
                // switch the user is looking for read the same.
                Text("Allow Full Access to enable haptics.")
                    .font(BrandFont.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            if install.isKeyboardInstalled {
                halo("checkmark.seal.fill", tint: .green)
                title("You're all set")
                    .padding(.top, 28)
                message("Tap the globe key to switch to Obadh.")
                    .padding(.top, 14)
            } else {
                halo("keyboard")
                title("Ready when you are")
                    .padding(.top, 28)
                message("Turn Obadh on any time in Settings › Keyboards.")
                    .padding(.top, 14)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 6) {
            switch step {
            case .welcome:
                primaryButton("Get Started") { advance(to: .setup) }

            case .setup:
                if install.isKeyboardInstalled {
                    primaryButton("Continue") { advance(to: .done) }
                } else {
                    primaryButton("Open Settings", action: openSystemSettings)
                    // Without this the step is a trap: a user who cannot add the keyboard
                    // right now has no way forward.
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
