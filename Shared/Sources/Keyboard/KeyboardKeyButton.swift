import UIKit

final class KeyboardKeyButton: UIButton {
    let key: KeyboardKey
    private let spaceLanguageLabel = UILabel()
    private var keyPreviewCallout: KeyboardKeyPreviewCallout?
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
            setImage(UIImage(systemName: "face.smiling"), for: .normal)
            keyPreviewText = nil
        }
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
            if self.isHighlighted {
                self.showKeyPreview()
            } else {
                self.hideKeyPreview(animated: animated)
            }
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

    private func showKeyPreview() {
        guard
            currentMetrics.keyPreviewHeight > 0,
            let keyPreviewText,
            !keyPreviewText.isEmpty,
            let rowView = superview
        else {
            return
        }
        let container = rowView.superview ?? rowView

        let callout = keyPreviewCallout ?? KeyboardKeyPreviewCallout()
        keyPreviewCallout = callout
        callout.update(
            text: keyPreviewText,
            metrics: currentMetrics,
            traitCollection: traitCollection
        )

        let size = KeyboardKeyPreviewCallout.preferredSize(
            for: bounds,
            metrics: currentMetrics
        )
        let frameInContainer = convert(bounds, to: container)
        let desiredX = frameInContainer.midX - size.width / 2
        let clampedX = min(
            max(0, desiredX),
            max(0, container.bounds.width - size.width)
        )
        let y = max(0, frameInContainer.minY - size.height + currentMetrics.keyPreviewStemHeight + 2)

        if callout.superview !== container {
            callout.removeFromSuperview()
            container.addSubview(callout)
        }
        container.bringSubviewToFront(callout)
        callout.frame = CGRect(origin: CGPoint(x: clampedX, y: y), size: size)

        guard callout.alpha < 1 else {
            callout.transform = .identity
            return
        }

        callout.alpha = 0
        callout.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.055,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            callout.alpha = 1
            callout.transform = .identity
        }
    }

    private func hideKeyPreview(animated: Bool) {
        guard let callout = keyPreviewCallout else {
            return
        }

        let remove = {
            callout.removeFromSuperview()
            callout.transform = .identity
            self.keyPreviewCallout = nil
        }

        guard animated else {
            remove()
            return
        }

        UIView.animate(
            withDuration: 0.075,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn],
            animations: {
                callout.alpha = 0
                callout.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            },
            completion: { _ in
                remove()
            }
        )
    }
}
