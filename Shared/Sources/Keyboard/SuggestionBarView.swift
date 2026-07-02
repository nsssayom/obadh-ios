import UIKit

@MainActor
protocol SuggestionBarViewDelegate: AnyObject {
    func suggestionBar(_ suggestionBar: SuggestionBarView, didSelect suggestion: KeyboardSuggestion)
}

final class SuggestionBarView: UIView {
    weak var delegate: SuggestionBarViewDelegate?

    private var suggestions: [KeyboardSuggestion] = []
    private let stackView = UIStackView()
    private let firstSeparator = UIView()
    private let secondSeparator = UIView()
    private var slotControls: [SuggestionSlotControl] = []
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

    func update(suggestions: [KeyboardSuggestion]) {
        self.suggestions = suggestions
        let visibleSuggestions = Array(suggestions.prefix(3))
        let startIndex = visibleSuggestions.count == 1 ? 1 : 0
        let showsChrome = !visibleSuggestions.isEmpty
        stackView.isHidden = !showsChrome
        setSeparatorsHidden(!showsChrome)

        for (index, slotControl) in slotControls.enumerated() {
            let suggestionIndex = index - startIndex
            let suggestion = visibleSuggestions.indices.contains(suggestionIndex) ? visibleSuggestions[suggestionIndex] : nil
            slotControl.tag = suggestionIndex
            slotControl.update(
                suggestion: suggestion,
                showsChrome: showsChrome,
                traitCollection: traitCollection,
                metrics: metrics
            )
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
        update(suggestions: suggestions)
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

            NSLayoutConstraint(
                item: firstSeparator,
                attribute: .centerX,
                relatedBy: .equal,
                toItem: self,
                attribute: .trailing,
                multiplier: 1.0 / 3.0,
                constant: 0
            ),
            NSLayoutConstraint(
                item: secondSeparator,
                attribute: .centerX,
                relatedBy: .equal,
                toItem: self,
                attribute: .trailing,
                multiplier: 2.0 / 3.0,
                constant: 0
            ),
            firstSeparatorCenterYConstraint,
            secondSeparatorCenterYConstraint,
            firstSeparator.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.58),
            secondSeparator.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.58),
            firstSeparator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            secondSeparator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SuggestionBarView, _) in
            view.update(suggestions: view.suggestions)
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
        let updates = {
            self.backgroundColor = targetColor
        }

        guard animated else {
            updates()
            return
        }
        UIView.animate(
            withDuration: isHighlighted ? 0.05 : 0.10,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: updates
        )
    }
}
