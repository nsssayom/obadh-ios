import SwiftUI
import UIKit

// The icon's palette, reused so the app and the mark read as one thing.
// Gradient #16506F → #3CBFBC on #1E2124 charcoal.
extension Color {
    static let obadhDeep = Color(hex: 0x16506F)
    static let obadhTeal = Color(hex: 0x3CBFBC)
    static let obadhTealLight = Color(hex: 0x7FE3DF)
    static let obadhCharcoal = Color(hex: 0x1E2124)
    static let obadhCharcoalDeep = Color(hex: 0x15181A)
    static let obadhPaper = Color(hex: 0xF3F5F6)
    static let obadhPaperWarm = Color(hex: 0xFFFFFF)

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum BrandGradient {
    /// Runs light-to-dark on paper and dark-to-light on charcoal, so the wordmark
    /// never fades into its own background at either end of the sweep.
    static func wordmark(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [.obadhTealLight, .obadhTeal]
                : [.obadhDeep, .obadhTeal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Stops short of the bright teal end: white label text needs the darker half to
    /// stay legible.
    static let action = LinearGradient(
        colors: [.obadhDeep, Color(hex: 0x26839A)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// One scale for the whole first-run flow. Headings are rounded, matching the wordmark
/// and the curve of the অ in the mark; body stays SF Pro, which rounded reads childish
/// at.
enum BrandFont {
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static let title = Font.system(size: 30, weight: .bold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular)
    static let caption = Font.system(size: 14, weight: .regular)

    /// Kohinoor Bangla ships with iOS. Only Light/Regular/Semibold exist — asking for
    /// a weight it doesn't have silently returns nil, so fall back to the system face
    /// rather than render nothing.
    static func bangla(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        guard let font = UIFont(name: weight.postScriptName, size: size) else {
            return .system(size: size, weight: weight.systemWeight)
        }
        return Font(font)
    }

    enum Weight {
        case light, regular, semibold

        var postScriptName: String {
            switch self {
            case .light: "KohinoorBangla-Light"
            case .regular: "KohinoorBangla-Regular"
            case .semibold: "KohinoorBangla-Semibold"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .light: .light
            case .regular: .regular
            case .semibold: .semibold
            }
        }
    }
}

/// Two slow brand glows over a near-black (never pure black) base. Pure #000 reads as
/// "unstyled" on OLED; the charcoal from the icon reads as a decision.
///
/// Everything is sized and positioned as a fraction of the container. Fixed offsets
/// tuned on a 440pt phone land somewhere else entirely on a 375pt one.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driftA = false
    @State private var driftB = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                base

                glow(primary, opacity: scheme == .dark ? 0.30 : 0.22, diameter: width * 1.35)
                    .offset(
                        x: width * 0.06 + width * (driftA ? 0.05 : -0.05),
                        y: -height * 0.30 + height * (driftA ? 0.025 : -0.025)
                    )
                    .scaleEffect(driftA ? 1.06 : 0.95)
                    .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: driftA)

                glow(secondary, opacity: scheme == .dark ? 0.34 : 0.18, diameter: width * 1.15)
                    .offset(
                        x: -width * 0.30 + width * (driftB ? -0.045 : 0.045),
                        y: height * 0.32 + height * (driftB ? 0.03 : -0.03)
                    )
                    .scaleEffect(driftB ? 0.94 : 1.07)
                    .animation(.easeInOut(duration: 13).repeatForever(autoreverses: true), value: driftB)
            }
            .frame(width: width, height: height)
        }
        .ignoresSafeArea()
        .onAppear(perform: startDrift)
    }

    private var primary: Color { .obadhTeal }

    /// On charcoal the deep blue reads as light. Over near-white it reads as a grey
    /// smudge, so light mode gets a luminous blue-teal instead of the dark brand blue.
    private var secondary: Color {
        scheme == .dark ? .obadhDeep : Color(hex: 0x2E9FBF)
    }

    private var base: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [.obadhCharcoal, .obadhCharcoalDeep]
                : [.obadhPaperWarm, .obadhPaper],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func glow(_ color: Color, opacity: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.07)
    }

    /// Two incommensurate periods, so the pair never settles into a visible pulse.
    ///
    /// The repeating animation is declared on the views with `.animation(_:value:)`
    /// rather than wrapped around these assignments. A `withAnimation` issued from
    /// `onAppear` runs before the view is on screen and SwiftUI discards the
    /// transaction — the state flips, nothing moves, and the result looks identical to
    /// working code in a screenshot.
    private func startDrift() {
        guard !reduceMotion else { return }
        driftA = true
        driftB = true
    }
}

/// The app mark, lit so it separates from the background rather than dissolving into
/// it, and given just enough life to feel physical: a slow float, a breathing pool of
/// light behind it, and a specular sweep that crosses once every few seconds.
///
/// Every part of this is off under Reduce Motion.
struct BrandMark: View {
    var size: CGFloat = 112

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    @State private var pulsing = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .overlay { if !reduceMotion { sheen } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
            .shadow(color: .obadhTeal.opacity(0.30), radius: 28)
            .offset(y: floating ? -4 : 4)
            .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: floating)
            // A pool of light directly behind the mark: without it the charcoal squircle
            // sits on charcoal and reads as a smudge. As a background it overflows freely
            // without inflating the mark's frame — as a ZStack sibling it would drag the
            // wordmark 200pt down the screen.
            .background(spotlight)
            .onAppear(perform: startAmbientMotion)
    }

    private var spotlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.obadhTeal.opacity(0.42), .obadhDeep.opacity(0.20), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 1.35
                )
            )
            .frame(width: size * 2.7, height: size * 2.7)
            .blur(radius: 22)
            .scaleEffect(pulsing ? 1.06 : 0.94)
            .opacity(pulsing ? 1 : 0.85)
            .animation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true), value: pulsing)
    }

    /// A narrow specular band, held offscreen between passes so it reads as a glint
    /// rather than a loop. The reset hop happens while the band is clipped away.
    ///
    /// The gradient runs across the band's short axis. Down the long axis it would
    /// feather top-to-bottom and leave two hard vertical edges, which the rotation
    /// then drags across the icon as a visible diagonal seam.
    private var sheen: some View {
        LinearGradient(
            colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: size * 0.55, height: size * 2.2)
        .rotationEffect(.degrees(22))
        .blendMode(.plusLighter)
        .phaseAnimator([0, 1, 2]) { band, phase in
            band.offset(x: phase == 0 ? -size : size)
        } animation: { phase in
            switch phase {
            case 1: .easeInOut(duration: 1.9)   // the sweep
            case 2: .linear(duration: 4.2)      // hold, offscreen
            default: .linear(duration: 0.01)    // reset, invisible under the clip
            }
        }
    }

    /// Repeating animations are declared on the views, not wrapped around these flips.
    /// See `BrandBackground.startDrift` — a `withAnimation` from `onAppear` is silently
    /// discarded, so the icon simply never moves.
    private func startAmbientMotion() {
        guard !reduceMotion else { return }
        floating = true
        pulsing = true
    }
}

/// Staggered fade-and-rise. `index` orders the cascade; a step change re-triggers it.
struct Reveal: ViewModifier {
    let index: Int
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : 14)
            .blur(radius: reduceMotion || isVisible ? 0 : 3)
            .animation(
                .smooth(duration: 0.55).delay(reduceMotion ? 0 : Double(index) * 0.08),
                value: isVisible
            )
    }
}

extension View {
    func reveal(_ index: Int, isVisible: Bool) -> some View {
        modifier(Reveal(index: index, isVisible: isVisible))
    }
}

struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(BrandGradient.action, in: Capsule())
            .shadow(color: .obadhDeep.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
