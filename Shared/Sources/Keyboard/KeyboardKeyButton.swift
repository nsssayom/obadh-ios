import UIKit

final class KeyboardKeyButton: UIButton {
    let key: KeyboardKey
    private let spaceLanguageLabel = UILabel()
    private var keyPreviewText: String?
    private var currentMetrics = KeyboardTheme.defaultMetrics
    private var spaceLanguageTrailingConstraint: NSLayoutConstraint?
    private var spaceLanguageBottomConstraint: NSLayoutConstraint?

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
        spaceIntroText: String = "Bangla (Obadh)",
        spaceCaption: String = "বাংলা"
    ) {
        currentMetrics = metrics
        layer.cornerRadius = metrics.keyCornerRadius
        layer.shadowRadius = metrics.keyShadowRadius
        layer.shadowOffset = metrics.keyShadowOffset
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
        layer.shadowOpacity = KeyboardTheme.defaultMetrics.keyShadowOpacity
        layer.shadowRadius = KeyboardTheme.defaultMetrics.keyShadowRadius
        layer.shadowOffset = KeyboardTheme.defaultMetrics.keyShadowOffset
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center

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
            self.backgroundColor = self.backgroundColor(
                for: self.traitCollection,
                highlighted: self.isHighlighted
            )
            self.layer.shadowOpacity = self.isHighlighted
                ? max(0.25, self.currentMetrics.keyShadowOpacity - 0.12)
                : self.currentMetrics.keyShadowOpacity
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
        if let nativeImage = UIImage(systemName: "face.smiling.inverse", withConfiguration: configuration) {
            return nativeImage
        }

        let side = max(22, ceil(pointSize + 4))
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let faceBounds = CGRect(x: 1.2, y: 1.2, width: side - 2.4, height: side - 2.4)
            context.cgContext.setBlendMode(.copy)
            UIColor.black.setFill()
            UIBezierPath(ovalIn: faceBounds).fill()

            context.cgContext.setBlendMode(.clear)

            let eyeRadius = max(1.25, side * 0.055)
            let leftEye = CGRect(
                x: side * 0.34 - eyeRadius,
                y: side * 0.36 - eyeRadius,
                width: eyeRadius * 2,
                height: eyeRadius * 2
            )
            let rightEye = CGRect(
                x: side * 0.66 - eyeRadius,
                y: side * 0.36 - eyeRadius,
                width: eyeRadius * 2,
                height: eyeRadius * 2
            )
            context.cgContext.fillEllipse(in: leftEye)
            context.cgContext.fillEllipse(in: rightEye)

            let mouth = UIBezierPath()
            mouth.move(to: CGPoint(x: side * 0.34, y: side * 0.56))
            mouth.addCurve(
                to: CGPoint(x: side * 0.66, y: side * 0.56),
                controlPoint1: CGPoint(x: side * 0.39, y: side * 0.74),
                controlPoint2: CGPoint(x: side * 0.61, y: side * 0.74)
            )
            mouth.close()
            mouth.fill()
            context.cgContext.setBlendMode(.normal)
        }

        return image.withRenderingMode(.alwaysTemplate)
    }
}
