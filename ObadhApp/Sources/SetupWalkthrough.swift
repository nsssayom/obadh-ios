import SwiftUI

/// An animated diagram of what the user is about to do in Settings: tap Keyboards, turn
/// on Obadh, allow Full Access.
///
/// Drawn in Obadh's own idiom rather than as a pixel copy of Settings — it is a diagram,
/// not a forgery, and a fake that drifts from the real UI is worse than none. The rows
/// mirror what `Settings › Obadh` actually shows.
///
/// Under Reduce Motion it holds the final frame, which is the useful one.
struct SetupWalkthrough: View {
    /// Stage drives every derived flag below, so the whole diagram is one number.
    /// (stage, how long to hold it)
    private static let script: [(stage: Int, hold: Int)] = [
        (0, 1000),  // the Obadh page, at rest
        (1, 850),   // tap Keyboards
        (2, 700),   // pushed into Keyboards
        (3, 900),   // Obadh on
        (4, 1900)   // Full Access on
    ]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0

    private var showsKeyboardsPage: Bool { stage >= 2 }
    private var isTapping: Bool { stage == 1 }
    private var isObadhOn: Bool { stage >= 3 }
    private var isFullAccessOn: Bool { stage >= 4 }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.4)
            pages
        }
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(Color.obadhTeal.opacity(0.18), lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In Settings, tap Keyboards, turn on Obadh, then allow Full Access.")
        .task { await run() }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private var titleBar: some View {
        ZStack {
            Text(showsKeyboardsPage ? "Keyboards" : "Obadh")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .contentTransition(.opacity)

            HStack {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.obadhTeal)
                    .opacity(showsKeyboardsPage ? 1 : 0)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var pages: some View {
        ZStack {
            obadhPage
                .offset(x: showsKeyboardsPage ? -34 : 0)
                .opacity(showsKeyboardsPage ? 0 : 1)

            keyboardsPage
                .offset(x: showsKeyboardsPage ? 0 : 46)
                .opacity(showsKeyboardsPage ? 1 : 0)
        }
        .padding(14)
        .frame(height: 172)
    }

    private var obadhPage: some View {
        VStack(spacing: 0) {
            row("Apple Intelligence & Siri", "sparkles", .purple) { chevron }
            separator
            row("Search", "magnifyingglass", .gray) { chevron }
            separator
            row("Cellular Data", "antenna.radiowaves.left.and.right", .green) { miniToggle(on: true) }
            separator
            row("Keyboards", "keyboard", .gray) { chevron }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.obadhTeal.opacity(isTapping ? 0.22 : 0))
                )
                .overlay(alignment: .trailing) { tapRipple }
        }
    }

    private var keyboardsPage: some View {
        VStack(spacing: 0) {
            row("Obadh", "keyboard", .gray) { miniToggle(on: isObadhOn) }
            separator
            row("Allow Full Access", "hand.tap.fill", .orange) { miniToggle(on: isFullAccessOn) }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Pieces

    private func row(
        _ title: String,
        _ symbol: String,
        _ tint: Color,
        @ViewBuilder accessory: () -> some View
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(title)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var separator: some View {
        Divider().opacity(0.25).padding(.leading, 40)
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func miniToggle(on: Bool) -> some View {
        Capsule()
            .fill(on ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            }
    }

    /// The tap itself: a disc that swells on the Keyboards row and fades.
    private var tapRipple: some View {
        ZStack {
            Circle()
                .fill(Color.obadhTeal.opacity(0.30))
            Circle()
                .strokeBorder(Color.obadhTeal.opacity(0.9), lineWidth: 1.5)
        }
        .frame(width: 26, height: 26)
        .scaleEffect(isTapping ? 1.15 : 0.55)
        .opacity(isTapping ? 1 : 0)
        .offset(x: -1)
        .animation(.easeOut(duration: 0.45), value: isTapping)
    }

    private func run() async {
        guard !reduceMotion else {
            stage = Self.script.last?.stage ?? 0
            return
        }
        while !Task.isCancelled {
            for step in Self.script {
                withAnimation(.smooth(duration: 0.4)) { stage = step.stage }
                try? await Task.sleep(for: .milliseconds(step.hold))
                if Task.isCancelled { return }
            }
            withAnimation(.smooth(duration: 0.45)) { stage = 0 }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
