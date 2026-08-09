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
    /// iPad flick-down glyph. Measured off the reference capture: cap height 7pt
    /// (so ~10pt SF) with its cap top 10pt below the key top. Defaulted so the
    /// iPhone metrics and `defaultMetrics` need no change — they never draw it.
    var padSecondaryFontSize: CGFloat = 10
    var padSecondaryTopInset: CGFloat = 8
    /// The 13-inch iPad draws its number row shorter than the letter rows
    /// (45.5pt against 61pt). Zero means "every row is `minimumKeyHeight`",
    /// which is every other layout we ship.
    var padNumberRowHeight: CGFloat = 0
}

enum KeyboardTheme {
    /// Whether the host presents us in the LEGACY (pre-Liquid-Glass) keyboard
    /// container. There is no public API for this; the keyboard controller detects
    /// it from the presentation's transient sizing pass (see
    /// LegacyPresentationDetector) and sets this before relayout. Main-thread only,
    /// like every renderer that reads it. Gates both metrics (native legacy zone is
    /// 53pt with no system band) and the key palette (legacy keys: dark ≈ white
    /// @0.30 over panel, light = opaque white — both measured).
    @MainActor static var legacyPresentation = false

    #if DEBUG
    /// Diagnosis-only override making the strip carry the whole native zone, as if
    /// no system band were coming. Set solely by the debug panel's pinned-presentation
    /// control so the two layouts can be A/B'd on device; the shipping path never
    /// reads a runtime-detected value here. See KeyboardSizingLog.
    @MainActor static var debugFullZoneStrip = false
    #endif

    private static let referencePhoneWidth: CGFloat = 440
    /// The suggestion strip WE draw. In the modern presentation the system paints an
    /// unpaintable band above the extension inside its container, so the VISIBLE zone
    /// (container edge → q row) = band + strip.
    ///
    /// The band is a CONSTANT per OS, not a per-presentation variable. Measured on
    /// iOS 26.5 at 16.0pt and invariant under a swept asked height (217→307pt),
    /// repeated presentations, and host `inputAccessoryView`s of 0/44/88pt; measured
    /// on an iOS 27 device at 17.3pt in a third-party host. Apple describes it as the
    /// margin added above the keyboard's top row in iOS 26 (FB17978212).
    ///
    /// Do NOT reintroduce a runtime "is a band coming?" detector. One shipped briefly
    /// and keyed off the presentation's transient sizing heights, which are not
    /// stable (identical simulator presentations measured intermediates of 452 AND
    /// 481). Because the system pins our view's BOTTOM edge, changing this value
    /// moves every key row by the delta — a wrong guess re-shapes the whole keyboard,
    /// which is exactly the instability it was meant to cure.
    @MainActor
    private static var referenceSuggestionHeight: CGFloat {
        // Legacy presentation draws no system band, so the strip IS the zone
        // (native legacy zone: 53pt at every measured width).
        if legacyPresentation {
            return 53
        }
        #if DEBUG
        if debugFullZoneStrip {
            if #available(iOS 27.0, *) { return 54 }
            return 51
        }
        #endif
        // zone − band, per OS: iOS 27 native zone 54 − band ~17; iOS 26 zone ~51 − 16.
        if #available(iOS 27.0, *) {
            return 36
        }
        return 34
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
        keyPreviewStemHeight: 0,
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

    @MainActor
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
                    keyPreviewStemHeight: 0,
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
        // Type and key spacing scale with the taller iPad key; `scale` is capped at
        // 1.0, so without this an 834pt iPad drew 440pt-iPhone glyphs.
        let padFamily = traitCollection.userInterfaceIdiom == .pad
            ? KeyboardLayoutProvider.PadFamily.forWidth(Double(bounds.width))
            : nil
        let padTypeScale: CGFloat = padFamily == nil ? 1 : (padFamily == .extended ? 61.0 / 45.0 : 55.3 / 45.0)
        // The gap between keys is a per-family CONSTANT on iPad (12 / 10 / 7),
        // measured off native — not a scaled version of the phone's 6pt.
        let keySpacing = padFamily.map { CGFloat($0.gap) }
            ?? clamp(6 * scale, min: 5.25, max: 6)
        // Portrait key geometry is CLASS-QUANTIZED, not proportional to width —
        // measured against native across 375/393/402/420/430/440pt (iOS 26.5 sim,
        // modern + legacy hosts): pitch 54 / key 43 below ~410pt, pitch 56 / key 45
        // at 410pt and up, row gap 11 in both classes. The previous width/440
        // scaling shrank keys ~9% on Pro-class widths and sat the rows ~9pt below
        // native's (worst on SE-class, 18.5pt).
        // iPad is its own geometry class, and unlike iPhone its VERTICAL metrics do
        // not vary with width at all: measured across 744/820/834pt native key
        // height moves 0.5pt and total keyboard height 3pt, so both are family
        // constants. The 13-inch family is a different keyboard entirely — five
        // rows, taller keys, tighter gaps. See docs/native-parity-ipad.md.
        let compactWidthClass = bounds.width < 410
        let keyHeight: CGFloat = switch padFamily {
        case .extended: 61
        case .compact, .standard: 55.3
        case nil: compactWidthClass ? 43 : 45
        }
        let rowSpacing: CGFloat = switch padFamily {
        case .extended: 7.12
        case .compact, .standard: 8.9
        case nil: 11
        }
        let keyRowCount = padFamily == .extended ? 5 : 4
        let topInset: CGFloat = 0
        // Verified: with 6, class-B q-rows land exactly on native's (440: 663=663).
        // Class A solves to 3 from the measured chain (q = screen − dock − keyblock
        // − bottom + strip; native q 591 @ 402pt) — re-verified on-sim.
        // NOT native's 28/24. Those are measured from the SCREEN edge, and an iPad
        // input view does not reach it: the system's own keyboard container keeps a
        // 20pt band below us (measured identically on all five fleet widths — it is
        // not the safe area, which reports 5). Our view's bottom edge is therefore
        // already 20pt up, so the inset we apply is native's gap minus that band.
        // Verified by screenshot: with these values the last key row lands on
        // native's to within a point on every class.
        let padSystemBottomBand: CGFloat = 20
        let bottomInset: CGFloat = switch padFamily {
        case .extended: 24 - padSystemBottomBand
        case .compact, .standard: 28 - padSystemBottomBand
        case nil: compactWidthClass ? 3 : 6
        }
        // The strip takes the remainder of the actual bounds, so if a host hands us
        // a height other than the one we ask for, the strip flexes instead of the
        // keys drifting off native's rows.
        // The number row is shorter than the letter rows on the extended layout, so
        // the key block is not simply rowCount * keyHeight.
        let numberRowHeight: CGFloat = padFamily == .extended ? 45.5 : 0
        let keyBlockHeight = CGFloat(keyRowCount) * keyHeight
            - (numberRowHeight > 0 ? keyHeight - numberRowHeight : 0)
            + CGFloat(keyRowCount - 1) * rowSpacing
        let suggestionHeight = clamp(
            bounds.height - topInset - bottomInset - keyBlockHeight,
            min: 24,
            max: 96
        )
        return KeyboardMetrics(
            // Native's corner arc spans ~7pt at 440pt (measured: the top-row edge
            // inset decays 6.33 → 0 over 7 rows), drawn with a continuous curve.
            keyCornerRadius: clamp(7 * scale, min: 6, max: 7) * padTypeScale,
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
            keyPreviewStemHeight: 0,
            keyPreviewStemWidth: 24 * scale,
            keyPreviewCornerRadius: 10 * scale,
            keyPreviewShadowOpacity: 0.32,
            keyPreviewShadowRadius: 4 * scale,
            keyPreviewShadowOffset: CGSize(width: 0, height: 2 * scale),
            keyboardInsets: UIEdgeInsets(
                top: topInset,
                // Side margin is a measured per-family constant on iPad (6 / 9 / 3.5).
                left: padFamily.map { CGFloat($0.margin) } ?? clamp(6.67 * scale, min: 5.87, max: 6.67),
                bottom: bottomInset,
                right: padFamily.map { CGFloat($0.margin) } ?? clamp(6.67 * scale, min: 5.87, max: 6.67)
            ),
            characterFontSize: 23 * scale * padTypeScale,
            symbolFontSize: 21 * scale * padTypeScale,
            keyPreviewFontSize: 32 * scale,
            commandFontSize: 21 * scale * padTypeScale,
            modeSwitchFontSize: 17 * scale * padTypeScale,
            spaceIntroFontSize: 18,
            spaceLanguageFontSize: 11,
            suggestionFontSize: 15,
            deterministicSuggestionFontSize: 15,
            padSecondaryFontSize: padFamily == .extended ? 11 : 10,
            padSecondaryTopInset: padFamily == .extended ? 9 : 8,
            padNumberRowHeight: padFamily == .extended ? 45.5 : 0
        )
    }

    @MainActor
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

        // Class-quantized like the metrics: key 43 / pitch 54 / bottom 3 below
        // ~410pt, key 45 / pitch 56 / bottom 6 above (native-measured; see
        // metrics(for:)).
        // iPad portrait. Measured native totals are 322.5 / 319.5 / 322.5 / 385.5 /
        // 385.5pt across 744 / 820 / 834 / 1024 / 1032 — constant per family, with
        // 45.4pt of that being the system shortcut bar, which iOS draws above the
        // extension and is not part of the height we request. Keep in step with
        // metrics(for:) or the rows drift off the height we ask for.
        if traitCollection.userInterfaceIdiom == .pad {
            switch KeyboardLayoutProvider.PadFamily.forWidth(Double(shorterSide)) {
            case .extended:
                return referenceSuggestionHeight + 45.5 + 4 * 61 + 4 * 7.12 + 4
            case .compact, .standard:
                return referenceSuggestionHeight + 4 * 55.3 + 3 * 8.9 + 8
            }
        }
        let compact = shorterSide < 410
        let keyHeight: CGFloat = compact ? 43 : 45
        let bottomInset: CGFloat = compact ? 3 : 6
        let classHeight = referenceSuggestionHeight + 4 * keyHeight + 3 * 11 + bottomInset
        let minimumHeight = shorterSide >= 600 ? min(longerSide * 0.20, 320) : 199
        return clamp(classHeight, min: minimumHeight, max: max(minimumHeight, classHeight))
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
    /// The measured key fill. No debug overrides reach this: a persisted override
    /// pref once survived reinstalls and silently re-tinted dark mode, so the shipped
    /// values are the only values, in every build configuration.
    ///
    /// Rest alphas solved from same-backdrop screenshot sampling against native
    /// (iOS 26.5, modern presentation, mid-gray measurement background):
    /// dark — native key 78 over panel 44 → white @ (78−44)/(255−44) ≈ 0.16;
    /// light — native key ~246.5 over panel ~192 → white @ ≈ 0.87.
    /// Pressed lifts keep the shipped relative feel.
    @MainActor
    static func glassKeyTint(for traitCollection: UITraitCollection, highlighted: Bool) -> UIColor {
        let isDark = traitCollection.userInterfaceStyle == .dark
        if legacyPresentation {
            // Measured against legacy native: dark key 129 over panel 74 → white
            // @ (129−74)/(255−74) ≈ 0.30; light keys are opaque white (255).
            if isDark {
                return UIColor.white.withAlphaComponent(highlighted ? 0.51 : 0.30)
            }
            return UIColor.white.withAlphaComponent(highlighted ? 0.94 : 1.0)
        }
        if isDark {
            return UIColor.white.withAlphaComponent(highlighted ? 0.37 : 0.16)
        }
        return UIColor.white.withAlphaComponent(highlighted ? 0.94 : 0.87)
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
