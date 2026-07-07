import CoreHaptics
import UIKit

/// Key-press haptics tuned to Apple's own keyboard: a single, crisp "tick". The
/// exact system pattern is private, so we reproduce its *character* — a
/// high-sharpness transient — via Core Haptics (the only public API exposing the
/// sharpness/crispness axis). Below that we fall back to a `.rigid` impact (the
/// snappiest `UIImpactFeedbackGenerator` preset).
///
/// The native keyboard plays essentially ONE uniform tick for every printing key,
/// so this is a single transient — **intensity 0.5 / sharpness 0.9** — dialed in
/// on-device by the product owner to match Apple's keyboard. High sharpness keeps
/// it a definite tick (not a mush); moderate intensity keeps it from feeling
/// heavy. The emoji/globe language key stays silent, mirroring the native
/// keyboard; a word/sentence backspace is a touch firmer as a "larger delete"
/// cue. Haptics require Full Access and the user's system haptic setting; the
/// controller degrades to silence when either is missing.
@MainActor
final class KeyboardFeedbackController {
    /// Fallback impact generator (used when Core Haptics is unavailable).
    private let rigidFeedback = UIImpactFeedbackGenerator(style: .rigid)

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?

    private let preferences = KeyboardPreferences()
    private var hapticFeedbackEnabled = true

    /// One crisp transient: intensity + sharpness (each 0…1), plus the intensity
    /// to use for the `.rigid` impact fallback.
    private struct Tick {
        let intensity: Float
        let sharpness: Float
        let fallbackIntensity: CGFloat

        init(_ intensity: Float, _ sharpness: Float, fallback: CGFloat) {
            self.intensity = intensity
            self.sharpness = sharpness
            self.fallbackIntensity = fallback
        }
    }

    /// The shipped key-press tick (owner-tuned on-device to match native).
    private static let standardTick = Tick(0.5, 0.9, fallback: 0.55)

    // MARK: Lifecycle

    func prepare() {
        reloadPreferences()
        rigidFeedback.prepare()
        startEngine()
    }

    func reloadPreferences() {
        hapticFeedbackEnabled = preferences.hapticFeedbackEnabled
    }

    private func startEngine() {
        guard supportsHaptics, hapticFeedbackEnabled, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engine = nil }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
            // Prewarm with an imperceptible zero-intensity transient so the first
            // real key tap doesn't pay the engine's cold-start latency.
            try? play(intensity: 0, sharpness: 0)
        } catch {
            engine = nil
        }
    }

    // MARK: Public API

    func keyTouched(_ key: KeyboardKey) {
        // One uniform tick for every printing key; the emoji/globe language key
        // stays silent, matching Apple's own keyboard.
        if hapticFeedbackEnabled, key != .emoji {
            emit(Self.standardTick)
        }
        UIDevice.current.playInputClick()
    }

    func suggestionAccepted() {
        if hapticFeedbackEnabled {
            emit(Self.standardTick)
        }
        UIDevice.current.playInputClick()
    }

    func backspaceRepeated(unit: BackspaceDeletionUnit) {
        if hapticFeedbackEnabled {
            switch unit {
            case .character:
                emit(Self.standardTick)
            case .word, .sentence, .availableContext:
                emit(Tick(0.6, 0.9, fallback: 0.65)) // a touch firmer for a larger delete
            }
        }
        UIDevice.current.playInputClick()
    }

    // MARK: Playback

    private func emit(_ tick: Tick) {
        var tick = tick
        #if DEBUG
        // Live tuning: when the app's debug sliders are engaged, every tick uses
        // the same dialed-in intensity/sharpness so the feel can be matched on
        // hardware. Read fresh each keystroke to pick up slider changes.
        let prefs = KeyboardPreferences()
        if prefs.debugHapticOverrideEnabled {
            tick = Tick(
                Float(prefs.debugHapticIntensity),
                Float(prefs.debugHapticSharpness),
                fallback: CGFloat(prefs.debugHapticIntensity)
            )
        }
        #endif
        if supportsHaptics, engine != nil {
            do {
                try play(intensity: tick.intensity, sharpness: tick.sharpness)
                return
            } catch {
                engine = nil // died between taps → fall through and relight
            }
        }
        rigidFeedback.impactOccurred(intensity: tick.fallbackIntensity)
        rigidFeedback.prepare()
        startEngine()
    }

    private func play(intensity: Float, sharpness: Float) throws {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: CHHapticTimeImmediate)
    }
}
