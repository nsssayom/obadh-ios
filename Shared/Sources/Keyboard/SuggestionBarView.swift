import UIKit

/// One inline emoji suggestion: `display` is what's shown/inserted (already
/// resolved to the user's preferred skin tone), `base` is the neutral form used
/// to look up skin-tone variants on long-press.
struct EmojiSuggestion: Equatable {
    let base: String
    let display: String
}

@MainActor
protocol SuggestionBarViewDelegate: AnyObject {
    func suggestionBar(_ suggestionBar: SuggestionBarView, didSelect suggestion: KeyboardSuggestion)
    func suggestionBar(_ suggestionBar: SuggestionBarView, didSelectEmoji emoji: String)
    /// A skin-tone variant was picked via long-press; host should remember it and insert.
    func suggestionBar(_ suggestionBar: SuggestionBarView, didPickEmojiVariant emoji: String, base: String)
    /// Skin-tone options (base + variants) for an emoji, loaded lazily on long-press only.
    func suggestionBar(_ suggestionBar: SuggestionBarView, variantOptionsFor base: String) -> [EmojiItem]
}

final class SuggestionBarView: UIView {
    weak var delegate: SuggestionBarViewDelegate?

    private var suggestions: [KeyboardSuggestion] = []
    private var emojis: [EmojiSuggestion] = []
    private let stackView = UIStackView()
    private let firstSeparator = UIView()
    private let secondSeparator = UIView()
    private var slotControls: [SuggestionSlotControl] = []
    private let emojiGroup = EmojiSuggestionGroupView()
    private var variantPopover: EmojiVariantPopoverView?
    private var variantPopoverBase: String?
    private var heightConstraint: NSLayoutConstraint?
    private var contentTopConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private var firstSeparatorCenterYConstraint: NSLayoutConstraint?
    private var secondSeparatorCenterYConstraint: NSLayoutConstraint?
    private var metrics = KeyboardTheme.defaultMetrics

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(suggestions: [KeyboardSuggestion], emojis: [EmojiSuggestion] = []) {
        self.suggestions = suggestions
        self.emojis = Array(emojis.prefix(3))
        let visibleSuggestions = Array(suggestions.prefix(3))
        let hasEmoji = !self.emojis.isEmpty
        let startIndex = (!hasEmoji && visibleSuggestions.count == 1) ? 1 : 0
        let textSlotCount = hasEmoji ? 2 : 3
        let showsChrome = !visibleSuggestions.isEmpty || hasEmoji
        stackView.isHidden = !showsChrome
        setSeparatorsHidden(!showsChrome)

        for (index, slotControl) in slotControls.enumerated() {
            let suggestionIndex = index - startIndex
            let withinTextSlots = index < textSlotCount
            let suggestion = withinTextSlots && visibleSuggestions.indices.contains(suggestionIndex)
                ? visibleSuggestions[suggestionIndex]
                : nil
            slotControl.tag = suggestionIndex
            slotControl.update(
                suggestion: suggestion,
                showsChrome: showsChrome,
                traitCollection: traitCollection,
                metrics: metrics
            )
        }

        emojiGroup.isHidden = !hasEmoji
        if hasEmoji {
            emojiGroup.update(emojis: self.emojis, traitCollection: traitCollection, metrics: metrics)
        } else {
            dismissVariantPopover(animated: false)
        }

        let separatorColor = KeyboardTheme.separatorColor(for: traitCollection)
        firstSeparator.backgroundColor = separatorColor
        secondSeparator.backgroundColor = separatorColor
    }

    func applyMetrics(_ metrics: KeyboardMetrics) {
        self.metrics = metrics
        heightConstraint?.constant = metrics.suggestionHeight
        contentTopConstraint?.constant = metrics.suggestionContentTopInset
        contentBottomConstraint?.constant = -metrics.suggestionContentBottomInset
        firstSeparatorCenterYConstraint?.constant = contentVerticalOffset(for: metrics)
        secondSeparatorCenterYConstraint?.constant = contentVerticalOffset(for: metrics)
        update(suggestions: suggestions, emojis: emojis)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        for _ in 0..<3 {
            let slotControl = SuggestionSlotControl()
            slotControl.addTarget(self, action: #selector(handleSuggestionTap(_:)), for: .touchUpInside)
            slotControls.append(slotControl)
            stackView.addArrangedSubview(slotControl)
        }
        configureSeparator(firstSeparator)
        configureSeparator(secondSeparator)

        emojiGroup.translatesAutoresizingMaskIntoConstraints = false
        emojiGroup.isHidden = true
        emojiGroup.onSelect = { [weak self] emoji in
            guard let self else { return }
            self.delegate?.suggestionBar(self, didSelectEmoji: emoji)
        }
        addSubview(emojiGroup)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleEmojiLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        emojiGroup.addGestureRecognizer(longPress)

        let heightConstraint = heightAnchor.constraint(equalToConstant: metrics.suggestionHeight)
        self.heightConstraint = heightConstraint
        let contentTopConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: metrics.suggestionContentTopInset)
        let contentBottomConstraint = stackView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -metrics.suggestionContentBottomInset
        )
        self.contentTopConstraint = contentTopConstraint
        self.contentBottomConstraint = contentBottomConstraint

        let firstSeparatorCenterYConstraint = firstSeparator.centerYAnchor.constraint(
            equalTo: centerYAnchor,
            constant: contentVerticalOffset(for: metrics)
        )
        let secondSeparatorCenterYConstraint = secondSeparator.centerYAnchor.constraint(
            equalTo: centerYAnchor,
            constant: contentVerticalOffset(for: metrics)
        )
        self.firstSeparatorCenterYConstraint = firstSeparatorCenterYConstraint
        self.secondSeparatorCenterYConstraint = secondSeparatorCenterYConstraint

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentTopConstraint,
            contentBottomConstraint,
            heightConstraint,

            emojiGroup.leadingAnchor.constraint(equalTo: slotControls[2].leadingAnchor),
            emojiGroup.trailingAnchor.constraint(equalTo: slotControls[2].trailingAnchor),
            emojiGroup.topAnchor.constraint(equalTo: slotControls[2].topAnchor),
            emojiGroup.bottomAnchor.constraint(equalTo: slotControls[2].bottomAnchor),

            NSLayoutConstraint(
                item: firstSeparator, attribute: .centerX, relatedBy: .equal,
                toItem: self, attribute: .trailing, multiplier: 1.0 / 3.0, constant: 0
            ),
            NSLayoutConstraint(
                item: secondSeparator, attribute: .centerX, relatedBy: .equal,
                toItem: self, attribute: .trailing, multiplier: 2.0 / 3.0, constant: 0
            ),
            firstSeparatorCenterYConstraint,
            secondSeparatorCenterYConstraint,
            firstSeparator.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.58),
            secondSeparator.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.58),
            firstSeparator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            secondSeparator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SuggestionBarView, _) in
            view.update(suggestions: view.suggestions, emojis: view.emojis)
        }

        update(suggestions: [])
    }

    private func configureSeparator(_ separator: UIView) {
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isUserInteractionEnabled = false
        separator.isHidden = true
        addSubview(separator)
    }

    private func setSeparatorsHidden(_ hidden: Bool) {
        firstSeparator.isHidden = hidden
        secondSeparator.isHidden = hidden
    }

    private func contentVerticalOffset(for metrics: KeyboardMetrics) -> CGFloat {
        -min(7, max(4, metrics.suggestionHeight * 0.20))
    }

    @objc private func handleSuggestionTap(_ sender: UIControl) {
        guard suggestions.indices.contains(sender.tag) else { return }
        delegate?.suggestionBar(self, didSelect: suggestions[sender.tag])
    }

    // MARK: Emoji skin-tone long-press

    @objc private func handleEmojiLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let point = gesture.location(in: emojiGroup)
            guard let (suggestion, cellFrame) = emojiGroup.suggestion(at: point) else { return }
            let options = delegate?.suggestionBar(self, variantOptionsFor: suggestion.base) ?? []
            guard options.count > 1 else { return }
            showVariantPopover(options: options, base: suggestion.base, cellFrame: emojiGroup.convert(cellFrame, to: self))
        case .changed:
            variantPopover?.updateSelection(at: gesture.location(in: self))
        case .ended:
            if let base = variantPopoverBase, let item = variantPopover?.selectedItem {
                delegate?.suggestionBar(self, didPickEmojiVariant: item.emoji, base: base)
            }
            dismissVariantPopover(animated: true)
        case .cancelled, .failed:
            dismissVariantPopover(animated: true)
        default:
            break
        }
    }

    private func showVariantPopover(options: [EmojiItem], base: String, cellFrame: CGRect) {
        dismissVariantPopover(animated: false)
        let popover = EmojiVariantPopoverView(options: options)
        popover.updateTheme(traitCollection: traitCollection)
        addSubview(popover)

        let size = popover.preferredSize
        let x = min(max(4, cellFrame.midX - size.width / 2), max(4, bounds.width - size.width - 4))
        // Present BELOW the bar (over the top key rows) — the bar sits at the very
        // top of the keyboard, so there's no room above it.
        let y = cellFrame.maxY + 6
        popover.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        popover.updateSelection(at: CGPoint(x: cellFrame.midX, y: cellFrame.midY))
        variantPopover = popover
        variantPopoverBase = base

        popover.alpha = 0
        popover.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            popover.alpha = 1
            popover.transform = .identity
        }
    }

    private func dismissVariantPopover(animated: Bool) {
        guard let popover = variantPopover else { return }
        variantPopover = nil
        variantPopoverBase = nil
        guard animated else { popover.removeFromSuperview(); return }
        UIView.animate(withDuration: 0.1, animations: {
            popover.alpha = 0
            popover.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }, completion: { _ in popover.removeFromSuperview() })
    }
}

private final class SuggestionSlotControl: UIControl {
    private let label = UILabel()
    private var isSelectableSuggestion = false

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        suggestion: KeyboardSuggestion?,
        showsChrome: Bool,
        traitCollection: UITraitCollection,
        metrics: KeyboardMetrics
    ) {
        label.text = suggestion?.text
        label.textColor = suggestion == nil ? .clear : KeyboardTheme.secondaryTextColor(for: traitCollection)
        label.font = font(for: suggestion, metrics: metrics)
        label.transform = CGAffineTransform(translationX: 0, y: -min(7, max(4, metrics.suggestionHeight * 0.20)))
        isSelectableSuggestion = suggestion.map { $0.source != .deterministic } ?? false
        isEnabled = isSelectableSuggestion
        accessibilityLabel = suggestion?.text
        accessibilityTraits = isSelectableSuggestion ? .button : .staticText
        applyHighlightedState(animated: false)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20, weight: .regular)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func font(for suggestion: KeyboardSuggestion?, metrics: KeyboardMetrics) -> UIFont {
        guard let suggestion else {
            return .systemFont(ofSize: metrics.suggestionFontSize, weight: .regular)
        }
        switch suggestion.source {
        case .deterministic:
            return .systemFont(ofSize: metrics.deterministicSuggestionFontSize, weight: .regular)
        case .autocorrect, .autosuggest:
            return .systemFont(ofSize: metrics.suggestionFontSize, weight: .regular)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            applyHighlightedState(animated: true)
        }
    }

    private func applyHighlightedState(animated: Bool) {
        let targetColor = isHighlighted && isSelectableSuggestion
            ? KeyboardTheme.suggestionHighlightColor(for: traitCollection)
            : .clear
        let updates = { self.backgroundColor = targetColor }
        guard animated else { updates(); return }
        UIView.animate(
            withDuration: isHighlighted ? 0.05 : 0.10,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: updates
        )
    }
}

/// The trailing emoji region: up to 3 evenly-sized emoji cells with hairline
/// dividers (matching the native keyboard's emoji suggestions).
private final class EmojiSuggestionGroupView: UIView {
    var onSelect: ((String) -> Void)?
    private let stackView = UIStackView()
    private var cells: [EmojiCellControl] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        for _ in 0..<3 {
            let cell = EmojiCellControl()
            cell.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
            cells.append(cell)
            stackView.addArrangedSubview(cell)
        }
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(emojis: [EmojiSuggestion], traitCollection: UITraitCollection, metrics: KeyboardMetrics) {
        for (index, cell) in cells.enumerated() {
            if emojis.indices.contains(index) {
                cell.isHidden = false
                cell.update(
                    suggestion: emojis[index],
                    showsLeadingDivider: index > 0,
                    traitCollection: traitCollection,
                    metrics: metrics
                )
            } else {
                cell.isHidden = true
                cell.update(suggestion: nil, showsLeadingDivider: false, traitCollection: traitCollection, metrics: metrics)
            }
        }
    }

    /// The (suggestion, cellFrame-in-group) under a point, for the long-press picker.
    func suggestion(at point: CGPoint) -> (EmojiSuggestion, CGRect)? {
        for cell in cells where !cell.isHidden {
            if cell.frame.contains(point), let suggestion = cell.suggestion {
                return (suggestion, cell.frame)
            }
        }
        return nil
    }

    @objc private func handleTap(_ sender: EmojiCellControl) {
        guard let display = sender.suggestion?.display else { return }
        onSelect?(display)
    }
}

private final class EmojiCellControl: UIControl {
    private(set) var suggestion: EmojiSuggestion?
    private let label = UILabel()
    private let leadingDivider = UIView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)

        leadingDivider.translatesAutoresizingMaskIntoConstraints = false
        leadingDivider.isUserInteractionEnabled = false
        addSubview(leadingDivider)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            leadingDivider.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingDivider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            leadingDivider.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.58)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(suggestion: EmojiSuggestion?, showsLeadingDivider: Bool, traitCollection: UITraitCollection, metrics: KeyboardMetrics) {
        self.suggestion = suggestion
        label.text = suggestion?.display
        label.font = .systemFont(ofSize: metrics.suggestionFontSize + 4, weight: .regular)
        label.transform = CGAffineTransform(translationX: 0, y: -min(7, max(4, metrics.suggestionHeight * 0.20)))
        leadingDivider.isHidden = !showsLeadingDivider
        leadingDivider.backgroundColor = KeyboardTheme.separatorColor(for: traitCollection)
        isEnabled = suggestion != nil
        accessibilityLabel = suggestion?.display
        accessibilityTraits = .button
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            backgroundColor = isHighlighted && isEnabled
                ? KeyboardTheme.suggestionHighlightColor(for: traitCollection)
                : .clear
        }
    }
}
