import UIKit

@MainActor
final class KeyboardFeedbackController {
    private let keyFeedback = UIImpactFeedbackGenerator(style: .light)
    private let commandKeyFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let preferences = KeyboardPreferences()
    private var hapticFeedbackEnabled = true

    func prepare() {
        reloadPreferences()
        keyFeedback.prepare()
        commandKeyFeedback.prepare()
        selectionFeedback.prepare()
    }

    func reloadPreferences() {
        hapticFeedbackEnabled = preferences.hapticFeedbackEnabled
    }

    func keyTouched(_ key: KeyboardKey) {
        if hapticFeedbackEnabled {
            switch key {
            case .backspace:
                playCommandImpact(intensity: 0.78)
            case .space, .returnKey:
                playCommandImpact(intensity: 0.68)
            case .modeSwitch, .emoji:
                playCommandImpact(intensity: 0.58)
            case .shift:
                playSelection()
                playKeyImpact(intensity: 0.46)
            default:
                playKeyImpact(intensity: 0.72)
            }
        }
        UIDevice.current.playInputClick()
    }

    func suggestionAccepted() {
        if hapticFeedbackEnabled {
            playSelection()
        }
        UIDevice.current.playInputClick()
    }

    func backspaceRepeated(unit: BackspaceDeletionUnit) {
        guard hapticFeedbackEnabled else {
            UIDevice.current.playInputClick()
            return
        }

        switch unit {
        case .character:
            playCommandImpact(intensity: 0.54)
        case .word, .sentence, .availableContext:
            playSelection()
        }
        UIDevice.current.playInputClick()
    }

    private func playKeyImpact(intensity: CGFloat) {
        keyFeedback.impactOccurred(intensity: intensity)
        keyFeedback.prepare()
    }

    private func playCommandImpact(intensity: CGFloat) {
        commandKeyFeedback.impactOccurred(intensity: intensity)
        commandKeyFeedback.prepare()
    }

    private func playSelection() {
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }
}
