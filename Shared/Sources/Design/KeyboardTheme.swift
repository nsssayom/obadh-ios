import UIKit

/// How keys are filled. The native iOS 26 keyboard reads as a flat translucent
/// material WITHOUT a prominent specular rim; `UIGlassEffect(.regular)` adds a
/// raised white edge highlight that the native keys lack, so `.translucent`
/// (a plain semi-transparent fill) is the shipped default. DEBUG builds can flip
/// this at runtime via the debug channel to dial the material in on real
/// hardware (the simulator cannot render Liquid Glass faithfully); Release is
/// fixed to the shipped value.
enum KeyboardGlassStyle: String {
    case regular      // UIGlassEffect(.regular) — Liquid Glass with specular rim
    case clear        // UIGlassEffect(.clear) — flatter/clearer glass
    case translucent  // plain semi-transparent fill, no rim (native-like)
    case solid        // opaque fill (pre-iOS 26 fallback look)

    #if DEBUG
    @MainActor static var current: KeyboardGlassStyle = .translucent
    #else
    static var current: KeyboardGlassStyle { .translucent }
    #endif
}

struct KeyboardMetrics {
    let keyCornerRadius: CGFloat
    let keyShadowOpacity: Float
    let keyShadowRadius: CGFloat
    let keyShadowOffset: CGSize
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let rowTouchExtension: CGFloat
    let keyTouchExtension: CGFloat
    let suggestionHeight: CGFloat
    let suggestionContentTopInset: CGFloat
    let suggestionContentBottomInset: CGFloat
    let minimumKeyHeight: CGFloat
    let keyPreviewHeight: CGFloat
    let keyPreviewMinimumWidth: CGFloat
    let keyPreviewHorizontalOutset: CGFloat
    let keyPreviewStemHeight: CGFloat
    let keyPreviewStemWidth: CGFloat
    let keyPreviewCornerRadius: CGFloat
    let keyPreviewShadowOpacity: Float
    let keyPreviewShadowRadius: CGFloat
    let keyPreviewShadowOffset: CGSize
    let keyboardInsets: UIEdgeInsets
    let characterFontSize: CGFloat
    let symbolFontSize: CGFloat
    let keyPreviewFontSize: CGFloat
    let commandFontSize: CGFloat
    let modeSwitchFontSize: CGFloat
    let spaceIntroFontSize: CGFloat
    let spaceLanguageFontSize: CGFloat
    let suggestionFontSize: CGFloat
    let deterministicSuggestionFontSize: CGFloat
}

enum KeyboardTheme {
    private static let referencePhoneWidth: CGFloat = 440
    /// Key block at scale 1: 4×45pt keys + 3×10.67pt row spacing + 6pt bottom inset.
    /// 45pt keys at 56pt pitch are measured equal to native's on iOS 26.5 (simulator)
    /// and iOS 27 (device screenshots, Notes).
    private static let referenceKeyBlockHeight: CGFloat = 4 * 45 + 3 * 10.67 + 6
    /// The suggestion strip WE draw. In the modern presentation the system paints an
    /// unpaintable band (~17-19pt) above the extension inside its container, so the
    /// VISIBLE zone (container edge → q row) = strip + band. Native zone, measured:
    /// 51.7pt on iOS 26.5 (sim), 60.7pt on iOS 27 (device). The strip is chosen per
    /// OS so strip + band lands exactly on the native zone.
    private static var referenceSuggestionHeight: CGFloat {
        if #available(iOS 27.0, *) {
            return 41.5
        }
        return 34
    }
    private static var referenceExtensionHeight: CGFloat {
        referenceKeyBlockHeight + referenceSuggestionHeight
    }
    private static let referenceLandscapeHeight: CGFloat = 220

    private static let fallbackMetrics = KeyboardMetrics(
        keyCornerRadius: 6,
        keyShadowOpacity: 0,
        keyShadowRadius: 0,
        keyShadowOffset: CGSize(width: 0, height: 0.5),
        rowSpacing: 10.67,
        keySpacing: 6,
        rowTouchExtension: 8,
        keyTouchExtension: 10,
        suggestionHeight: 51,
        suggestionContentTopInset: 0,
        suggestionContentBottomInset: 0,
        minimumKeyHeight: 45,
        keyPreviewHeight: 77,
        keyPreviewMinimumWidth: 56,
        keyPreviewHorizontalOutset: 16,
        keyPreviewStemHeight: 13,
        keyPreviewStemWidth: 24,
        keyPreviewCornerRadius: 10,
        keyPreviewShadowOpacity: 0.32,
        keyPreviewShadowRadius: 4,
        keyPreviewShadowOffset: CGSize(width: 0, height: 2),
        keyboardInsets: UIEdgeInsets(top: 6, left: 6.67, bottom: 6, right: 6.67),
        characterFontSize: 23,
        symbolFontSize: 21,
        keyPreviewFontSize: 32,
        commandFontSize: 21,
        modeSwitchFontSize: 17,
        spaceIntroFontSize: 18,
        spaceLanguageFontSize: 11,
        suggestionFontSize: 15,
        deterministicSuggestionFontSize: 15
    )

    static var defaultMetrics: KeyboardMetrics {
        fallbackMetrics
    }

    static func metrics(for bounds: CGSize, traitCollection: UITraitCollection) -> KeyboardMetrics {
        let isLandscape = bounds.width > bounds.height && traitCollection.verticalSizeClass == .compact
        guard bounds.width > 0, bounds.height > 0 else {
            return fallbackMetrics
        }

        if isLandscape {
            if bounds.height > 260 {
                let scale = clamp(bounds.height / 320, min: 0.92, max: 1.0)
                return KeyboardMetrics(
                    keyCornerRadius: 6,
                    keyShadowOpacity: 0,
                    keyShadowRadius: 0,
                    keyShadowOffset: CGSize(width: 0, height: 0.5),
                    rowSpacing: 10 * scale,
                    keySpacing: clamp(bounds.width * 0.006, min: 6, max: 9),
                    rowTouchExtension: 8,
                    keyTouchExtension: 10,
                    suggestionHeight: 42 * scale,
                    suggestionContentTopInset: 0,
                    suggestionContentBottomInset: 0,
                    minimumKeyHeight: 54 * scale,
                    keyPreviewHeight: 78 * scale,
                    keyPreviewMinimumWidth: 58 * scale,
                    keyPreviewHorizontalOutset: 16 * scale,
                    keyPreviewStemHeight: 13 * scale,
                    keyPreviewStemWidth: 24 * scale,
                    keyPreviewCornerRadius: 10 * scale,
                    keyPreviewShadowOpacity: 0.32,
                    keyPreviewShadowRadius: 4 * scale,
                    keyPreviewShadowOffset: CGSize(width: 0, height: 2 * scale),
                    keyboardInsets: UIEdgeInsets(
                        top: 8 * scale,
                        left: clamp(bounds.width * 0.006, min: 7, max: 10),
                        bottom: 8 * scale,
                        right: clamp(bounds.width * 0.006, min: 7, max: 10)
                    ),
                    characterFontSize: 27 * scale,
                    symbolFontSize: 25 * scale,
                    keyPreviewFontSize: 34 * scale,
                    commandFontSize: 24 * scale,
                    modeSwitchFontSize: 18 * scale,
                    spaceIntroFontSize: 18 * scale,
                    spaceLanguageFontSize: 11,
                    suggestionFontSize: 16,
                    deterministicSuggestionFontSize: 16
                )
            }

            let keySpacing = clamp(bounds.width * 0.0065, min: 5, max: 6)
            let suggestionHeight = clamp(bounds.height * 0.19, min: 38, max: 44)
            let rowSpacing = clamp(bounds.height * 0.032, min: 6.5, max: 7.5)
            let topInset = clamp(bounds.height * 0.035, min: 6, max: 8)
            let bottomInset = clamp(bounds.height * 0.018, min: 3.5, max: 5)
            let keyHeight = max(
                31,
                floor((bounds.height - suggestionHeight - topInset - bottomInset - 3 * rowSpacing) / 4)
            )
            return KeyboardMetrics(
                keyCornerRadius: 5.5,
                keyShadowOpacity: 0,
                keyShadowRadius: 0,
                keyShadowOffset: CGSize(width: 0, height: 0.5),
                rowSpacing: rowSpacing,
                keySpacing: keySpacing,
                rowTouchExtension: 7,
                keyTouchExtension: 9,
                suggestionHeight: suggestionHeight,
                suggestionContentTopInset: 0,
                suggestionContentBottomInset: 0,
                minimumKeyHeight: keyHeight,
                keyPreviewHeight: 0,
                keyPreviewMinimumWidth: 0,
                keyPreviewHorizontalOutset: 0,
                keyPreviewStemHeight: 0,
                keyPreviewStemWidth: 0,
                keyPreviewCornerRadius: 0,
                keyPreviewShadowOpacity: 0,
                keyPreviewShadowRadius: 0,
                keyPreviewShadowOffset: .zero,
            keyboardInsets: UIEdgeInsets(
                top: topInset,
                left: clamp(bounds.width * 0.003, min: 3, max: 4),
                bottom: bottomInset,
                right: clamp(bounds.width * 0.003, min: 3, max: 4)
            ),
                characterFontSize: 21,
                symbolFontSize: 19,
                keyPreviewFontSize: 0,
                commandFontSize: 19,
                modeSwitchFontSize: 16,
                spaceIntroFontSize: 16,
                spaceLanguageFontSize: 10,
                suggestionFontSize: 15,
                deterministicSuggestionFontSize: 15
            )
        }

        let scale = clamp(bounds.width / referencePhoneWidth, min: 0.88, max: 1.0)
        let keySpacing = clamp(6 * scale, min: 5.25, max: 6)
        let rowSpacing = clamp(10.67 * scale, min: 9.4, max: 10.67)
        // Portrait: keys keep the native-parity size derived from the reference
        // geometry (45pt at scale 1 — measured equal to native's); the suggestion
        // strip takes the remainder of the actual bounds, so if a host hands us a
        // height other than the one we ask for, the strip flexes instead of the keys
        // drifting off native's rows.
        let topInset: CGFloat = 0
        let bottomInset = 6 * scale
        let keyHeight = floor(
            (referenceExtensionHeight * scale - referenceSuggestionHeight * scale
                - topInset - bottomInset - 3 * rowSpacing) / 4
        )
        let suggestionHeight = clamp(
            bounds.height - topInset - bottomInset - 3 * rowSpacing - 4 * keyHeight,
            min: 24,
            max: 96
        )
        return KeyboardMetrics(
            keyCornerRadius: clamp(6 * scale, min: 5, max: 6),
            keyShadowOpacity: 0,
            keyShadowRadius: 0,
            keyShadowOffset: CGSize(width: 0, height: 0.5),
            rowSpacing: rowSpacing,
            keySpacing: keySpacing,
            rowTouchExtension: 8,
            keyTouchExtension: 10,
            suggestionHeight: suggestionHeight,
            suggestionContentTopInset: 0,
            suggestionContentBottomInset: 0,
            minimumKeyHeight: keyHeight,
            keyPreviewHeight: 77 * scale,
            keyPreviewMinimumWidth: 56 * scale,
            keyPreviewHorizontalOutset: 16 * scale,
            keyPreviewStemHeight: 13 * scale,
            keyPreviewStemWidth: 24 * scale,
            keyPreviewCornerRadius: 10 * scale,
            keyPreviewShadowOpacity: 0.32,
            keyPreviewShadowRadius: 4 * scale,
            keyPreviewShadowOffset: CGSize(width: 0, height: 2 * scale),
            keyboardInsets: UIEdgeInsets(
                top: topInset,
                left: clamp(6.67 * scale, min: 5.87, max: 6.67),
                bottom: bottomInset,
                right: clamp(6.67 * scale, min: 5.87, max: 6.67)
            ),
            characterFontSize: 23 * scale,
            symbolFontSize: 21 * scale,
            keyPreviewFontSize: 32 * scale,
            commandFontSize: 21 * scale,
            modeSwitchFontSize: 17 * scale,
            spaceIntroFontSize: 18,
            spaceLanguageFontSize: 11,
            suggestionFontSize: 15,
            deterministicSuggestionFontSize: 15
        )
    }

    static func preferredKeyboardHeight(
        for screenSize: CGSize,
        traitCollection: UITraitCollection
    ) -> CGFloat {
        let shorterSide = min(screenSize.width, screenSize.height)
        let longerSide = max(screenSize.width, screenSize.height)
        let isLandscape = traitCollection.verticalSizeClass == .compact || screenSize.width > screenSize.height

        if isLandscape {
            if shorterSide >= 600 {
                return clamp(shorterSide * 0.36, min: 300, max: 360)
            }
            return clamp(shorterSide * 0.50, min: 196, max: referenceLandscapeHeight)
        }

        let scaledHeight = referenceExtensionHeight * clamp(shorterSide / referencePhoneWidth, min: 0.88, max: 1.0)
        let minimumHeight = shorterSide >= 600 ? min(longerSide * 0.20, 320) : 199
        return clamp(scaledHeight, min: minimumHeight, max: max(minimumHeight, referenceExtensionHeight))
    }

    static func preferredEmojiKeyboardHeight(
        for screenSize: CGSize,
        traitCollection: UITraitCollection
    ) -> CGFloat {
        let shorterSide = min(screenSize.width, screenSize.height)
        let longerSide = max(screenSize.width, screenSize.height)
        let isLandscape = traitCollection.verticalSizeClass == .compact || screenSize.width > screenSize.height

        if isLandscape {
            return clamp(shorterSide * 0.58, min: 250, max: 330)
        }

        let scale = clamp(shorterSide / referencePhoneWidth, min: 0.88, max: 1.0)
        let fourRowEmojiHeight = 332 * scale
        let maximumHeight = longerSide * 0.42
        return clamp(fourRowEmojiHeight, min: 306 * scale, max: maximumHeight)
    }

    private static func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }

    static func primaryKeyColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1)
        }
        return UIColor.white.withAlphaComponent(0.96)
    }

    static func utilityKeyColor(for traitCollection: UITraitCollection) -> UIColor {
        primaryKeyColor(for: traitCollection)
    }

    static func highlightedPrimaryKeyColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.315, green: 0.315, blue: 0.325, alpha: 1)
        }
        return UIColor.white
    }

    static func highlightedUtilityKeyColor(for traitCollection: UITraitCollection) -> UIColor {
        highlightedPrimaryKeyColor(for: traitCollection)
    }

    /// Translucent tint layered over a Liquid Glass key (iOS 26+) so the colored
    /// backdrop refracts through — the rest state is faint, the pressed state
    /// brightens (mirroring the native key's touch-down lift). Unified for
    /// character and utility keys to match the current design, where
    /// `utilityKeyColor == primaryKeyColor`.
    ///
    /// Alphas are calibrated to Apple's own keys sampled on iOS 27 (native vs
    /// Obadh, dark/light × solid/gradient hosts). A neutral white tint, not a cool
    /// one: native's cool cast in some hosts comes from the backdrop refracting
    /// through the glass, so over a neutral backdrop native keys are neutral — a
    /// cool tint made ours read cool where native didn't. Light native keys are
    /// near-opaque white (~254), so the light alpha runs high; dark keys stay
    /// visibly translucent (~64).
    /// The tuned key fill. No debug overrides reach this: a persisted override pref
    /// once survived reinstalls and silently re-tinted dark mode, so the shipped
    /// values are the only values, in every build configuration.
    static func glassKeyTint(for traitCollection: UITraitCollection, highlighted: Bool) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(highlighted ? 0.40 : 0.19)
        }
        return UIColor.white.withAlphaComponent(highlighted ? 0.98 : 0.93)
    }


    static func keyPreviewColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.235, green: 0.235, blue: 0.243, alpha: 1)
        }
        return .white
    }

    static func textColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return .white
        }
        return .black
    }

    static func separatorColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.220, green: 0.220, blue: 0.227, alpha: 1)
        }
        return UIColor.black.withAlphaComponent(0.12)
    }

    static func secondaryTextColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.56)
        }
        return UIColor.black.withAlphaComponent(0.48)
    }

    static func suggestionHighlightColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.08)
        }
        return UIColor.black.withAlphaComponent(0.07)
    }

    static func emojiSearchBackgroundColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.12)
        }
        return UIColor.black.withAlphaComponent(0.08)
    }

    static func emojiPlaceholderColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.56)
        }
        return UIColor.black.withAlphaComponent(0.42)
    }

    static func emojiCategoryTintColor(selected: Bool, traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(selected ? 0.94 : 0.56)
        }
        return UIColor.black.withAlphaComponent(selected ? 0.88 : 0.48)
    }

    static func emojiCategorySelectedBackgroundColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.13)
        }
        return UIColor.black.withAlphaComponent(0.09)
    }

    static func emojiCellHighlightColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.14)
        }
        return UIColor.black.withAlphaComponent(0.10)
    }

    static func keyboardBackgroundColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.090, green: 0.090, blue: 0.090, alpha: 1)
        }
        return UIColor(red: 0.820, green: 0.843, blue: 0.882, alpha: 1)
    }

}
