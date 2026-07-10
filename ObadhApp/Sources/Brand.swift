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
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            base
            glow(.obadhTeal, opacity: scheme == .dark ? 0.30 : 0.20)
                .frame(width: 540, height: 540)
                .offset(x: 40, y: -300)
                .scaleEffect(breathing ? 1.08 : 0.94)
            glow(.obadhDeep, opacity: scheme == .dark ? 0.36 : 0.16)
                .frame(width: 460, height: 460)
                .offset(x: -150, y: 320)
                .scaleEffect(breathing ? 0.95 : 1.07)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
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

    private func glow(_ color: Color, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 250
                )
            )
            .blur(radius: 30)
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

    private func startAmbientMotion() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
            floating = true
        }
        withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
            pulsing = true
        }
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
