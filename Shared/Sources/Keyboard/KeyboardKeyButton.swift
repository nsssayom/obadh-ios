import UIKit

final class KeyboardKeyButton: UIButton {
    let key: KeyboardKey
    private let spaceLanguageLabel = UILabel()
    private var keyPreviewText: String?
    private var currentMetrics = KeyboardTheme.defaultMetrics
    private var spaceLanguageTrailingConstraint: NSLayoutConstraint?
    private var spaceLanguageBottomConstraint: NSLayoutConstraint?
    /// iOS 26+ Liquid Glass backing (a backmost, non-interactive glass view).
    /// nil below iOS 26, where the solid `backgroundColor` fill is used instead.
    /// Touches are owned entirely by `KeyboardTouchSurfaceView`, so this is purely
    /// visual (`isInteractive = false`).
    private var glassEffectView: UIVisualEffectView?

    init(key: KeyboardKey) {
        self.key = key
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(
        shifted: Bool,
        traitCollection: UITraitCollection,
        metrics: KeyboardMetrics,
        showsSpaceIntro: Bool = false,
        spaceIntroText: String = "বাংলা (অবাধ)",
        spaceCaption: String = "বাংলা"
    ) {
        currentMetrics = metrics
        layer.cornerRadius = metrics.keyCornerRadius
        layer.shadowRadius = metrics.keyShadowRadius
        layer.shadowOffset = metrics.keyShadowOffset
        if #available(iOS 26.0, *) {
            glassEffectView?.cornerConfiguration = .uniformCorners(radius: .fixed(metrics.keyCornerRadius))
        }
        spaceLanguageLabel.font = .systemFont(ofSize: metrics.spaceLanguageFontSize, weight: .regular)
        spaceLanguageTrailingConstraint?.constant = -max(8, metrics.keySpacing + 5)
        spaceLanguageBottomConstraint?.constant = -max(5, metrics.keyboardInsets.bottom + 3)

        applyPressedState(animated: false)
        setTitleColor(KeyboardTheme.textColor(for: traitCollection), for: .normal)
        tintColor = KeyboardTheme.textColor(for: traitCollection)
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: metrics.commandFontSize, weight: .regular),
            forImageIn: .normal
        )
        spaceLanguageLabel.textColor = KeyboardTheme.secondaryTextColor(for: traitCollection)

        switch key {
        case let .character(value):
            let displayText = shifted ? value.uppercased() : value
            setTitle(displayText, for: .normal)
            setImage(nil, for: .normal)
            titleLabel?.font = .systemFont(ofSize: metrics.characterFontSize, weight: .regular)
            keyPreviewText = displayText
        case let .symbol(symbol):
            setTitle(symbol.label, for: .normal)
            setImage(nil, for: .normal)
            titleLabel?.font = .systemFont(ofSize: metrics.symbolFontSize, weight: .regular)
            keyPreviewText = symbol.label
        case .space:
            setTitle(showsSpaceIntro ? spaceIntroText : nil, for: .normal)
            setImage(nil, for: .normal)
            titleLabel?.font = .systemFont(ofSize: metrics.spaceIntroFontSize, weight: .regular)
            spaceLanguageLabel.text = showsSpaceIntro ? nil : spaceCaption
            spaceLanguageLabel.alpha = showsSpaceIntro ? 0 : 1
            keyPreviewText = nil
        case .returnKey:
            setTitle(nil, for: .normal)
            setImage(UIImage(systemName: "arrow.turn.down.left"), for: .normal)
            keyPreviewText = nil
        case .shift:
            setTitle(nil, for: .normal)
            setImage(UIImage(systemName: shifted ? "shift.fill" : "shift"), for: .normal)
            keyPreviewText = nil
        case .backspace:
            setTitle(nil, for: .normal)
            setImage(UIImage(systemName: "delete.left"), for: .normal)
            keyPreviewText = nil
        case let .modeSwitch(value):
            setTitle(value, for: .normal)
            setImage(nil, for: .normal)
            titleLabel?.font = .systemFont(ofSize: metrics.modeSwitchFontSize, weight: .regular)
            keyPreviewText = nil
        case .emoji:
            setTitle(nil, for: .normal)
            setImage(nativeEmojiGlyph(pointSize: metrics.commandFontSize + 2), for: .normal)
            keyPreviewText = nil
        }
    }

    var previewText: String? {
        keyPreviewText
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = true
        layer.cornerRadius = KeyboardTheme.defaultMetrics.keyCornerRadius
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = KeyboardTheme.effectiveKeyShadowOpacity(
            KeyboardTheme.defaultMetrics.keyShadowOpacity
        )
        layer.shadowRadius = KeyboardTheme.defaultMetrics.keyShadowRadius
        layer.shadowOffset = KeyboardTheme.defaultMetrics.keyShadowOffset
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center

        // Only the `.regular`/`.clear` styles use a Liquid Glass effect view (its
        // specular rim is what the product owner flagged as "raised"); the
        // default `.translucent` and `.solid` use a plain fill in
        // applyPressedState instead. The touch surface owns hit-testing, so the
        // glass is non-interactive; the button's own layer keeps the shadow
        // (a clipped effect view can't cast an outer shadow).
        if #available(iOS 26.0, *) {
            let glassStyle: UIGlassEffect.Style?
            switch KeyboardGlassStyle.current {
            case .regular: glassStyle = .regular
            case .clear: glassStyle = .clear
            case .translucent, .solid: glassStyle = nil
            }
            if let glassStyle {
                let effect = UIGlassEffect(style: glassStyle)
                effect.isInteractive = false
                let effectView = UIVisualEffectView(effect: effect)
                effectView.isUserInteractionEnabled = false
                effectView.frame = bounds
                effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                effectView.cornerConfiguration = .uniformCorners(
                    radius: .fixed(KeyboardTheme.defaultMetrics.keyCornerRadius)
                )
                effectView.layer.cornerCurve = .continuous
                effectView.clipsToBounds = true
                insertSubview(effectView, at: 0)
                glassEffectView = effectView
            }
        }

        spaceLanguageLabel.translatesAutoresizingMaskIntoConstraints = false
        spaceLanguageLabel.font = .systemFont(
            ofSize: KeyboardTheme.defaultMetrics.spaceLanguageFontSize,
            weight: .regular
        )
        spaceLanguageLabel.textAlignment = .right
        spaceLanguageLabel.isHidden = key != .space
        spaceLanguageLabel.isUserInteractionEnabled = false
        addSubview(spaceLanguageLabel)

        let trailingConstraint = spaceLanguageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        let bottomConstraint = spaceLanguageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        spaceLanguageTrailingConstraint = trailingConstraint
        spaceLanguageBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            trailingConstraint,
            bottomConstraint
        ])
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            applyPressedState(animated: true)
        }
    }

    private func backgroundColor(for traitCollection: UITraitCollection, highlighted: Bool) -> UIColor {
        switch key {
        case .character, .symbol, .space:
            highlighted
                ? KeyboardTheme.highlightedPrimaryKeyColor(for: traitCollection)
                : KeyboardTheme.primaryKeyColor(for: traitCollection)
        case .shift, .backspace, .modeSwitch, .emoji, .returnKey:
            highlighted
                ? KeyboardTheme.highlightedUtilityKeyColor(for: traitCollection)
                : KeyboardTheme.utilityKeyColor(for: traitCollection)
        }
    }

    private func applyPressedState(animated: Bool) {
        let updates = {
            if #available(iOS 26.0, *), let effectView = self.glassEffectView,
               let effect = effectView.effect as? UIGlassEffect {
                // Glass path (.regular/.clear): the fill is the glass view; tint
                // it (brighter when pressed) instead of swapping a solid color.
                self.backgroundColor = .clear
                effect.tintColor = KeyboardTheme.glassKeyTint(
                    for: self.traitCollection,
                    highlighted: self.isHighlighted
                )
                effectView.effect = effect
            } else if KeyboardGlassStyle.current == .translucent {
                // Flat translucent fill: native-like "simple transparency" with
                // no specular rim / raised edge.
                self.backgroundColor = KeyboardTheme.glassKeyTint(
                    for: self.traitCollection,
                    highlighted: self.isHighlighted
                )
            } else {
                self.backgroundColor = self.backgroundColor(
                    for: self.traitCollection,
                    highlighted: self.isHighlighted
                )
            }
            let restShadow = KeyboardTheme.effectiveKeyShadowOpacity(self.currentMetrics.keyShadowOpacity)
            self.layer.shadowOpacity = self.isHighlighted
                ? max(0, restShadow - 0.12)
                : restShadow
            self.transform = self.isHighlighted
                ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                : .identity
        }

        guard animated else {
            updates()
            return
        }
        UIView.animate(
            withDuration: isHighlighted ? 0.045 : 0.075,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: updates
        )
    }

    private func nativeEmojiGlyph(pointSize: CGFloat) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        // Apple's own keyboard emoji key uses the PRIVATE symbol `emoji.face.grinning`
        // (a thin OUTLINE grinning face). That symbol is unavailable to third parties
        // (`UIImage(systemName:)` returns nil and private names risk review). The
        // faithful PUBLIC match is the OUTLINE `face.smiling` — NOT `face.smiling.inverse`,
        // which is a filled disc and was the visual mismatch vs. native. Rendered as a
        // template so `tintColor` (the key text color) applies.
        if let nativeImage = UIImage(systemName: "face.smiling", withConfiguration: configuration) {
            return nativeImage
        }

        // Fallback (dead in practice — face.smiling resolves on iOS 14+): stroke an
        // OUTLINE face so it stays consistent with the outline glyph above.
        let side = max(22, ceil(pointSize + 4))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let lineWidth = max(1, side * 0.05)
            UIColor.black.setStroke()

            let ring = UIBezierPath(ovalIn: CGRect(
                x: lineWidth,
                y: lineWidth,
                width: side - lineWidth * 2,
                height: side - lineWidth * 2
            ))
            ring.lineWidth = lineWidth
            ring.stroke()

            let eyeRadius = max(1, side * 0.05)
            for eyeCenterX in [side * 0.34, side * 0.66] {
                let eye = UIBezierPath(ovalIn: CGRect(
                    x: eyeCenterX - eyeRadius,
                    y: side * 0.38 - eyeRadius,
                    width: eyeRadius * 2,
                    height: eyeRadius * 2
                ))
                UIColor.black.setFill()
                eye.fill()
            }

            let mouth = UIBezierPath()
            mouth.move(to: CGPoint(x: side * 0.33, y: side * 0.58))
            mouth.addQuadCurve(
                to: CGPoint(x: side * 0.67, y: side * 0.58),
                controlPoint: CGPoint(x: side * 0.50, y: side * 0.72)
            )
            mouth.lineWidth = lineWidth
            mouth.lineCapStyle = .round
            mouth.stroke()
        }

        return image.withRenderingMode(.alwaysTemplate)
    }
}
