import UIKit

/// Drag-to-select skin-tone/variant popover, shared by the emoji panel and the
/// inline emoji suggestions (both drive it with a long-press gesture).
final class EmojiVariantPopoverView: UIView {
    private let options: [EmojiItem]
    private let stackView = UIStackView()
    private var optionLabels: [UILabel] = []
    private(set) var selectedIndex = 0

    var selectedItem: EmojiItem {
        options[selectedIndex]
    }

    var preferredSize: CGSize {
        CGSize(width: CGFloat(options.count) * 44 + 14, height: 54)
    }

    init(options: [EmojiItem]) {
        self.options = options
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTheme(traitCollection: UITraitCollection) {
        backgroundColor = KeyboardTheme.keyboardBackgroundColor(for: traitCollection).withAlphaComponent(0.96)
        layer.borderColor = KeyboardTheme.separatorColor(for: traitCollection).cgColor
        for label in optionLabels {
            label.textColor = KeyboardTheme.textColor(for: traitCollection)
        }
        updateSelectionHighlight(traitCollection: traitCollection)
    }

    func updateSelection(at pointInSuperview: CGPoint) {
        guard let superview else { return }
        let localPoint = convert(pointInSuperview, from: superview)
        for (index, label) in optionLabels.enumerated() {
            if label.frame.insetBy(dx: -5, dy: -8).contains(localPoint) {
                selectedIndex = index
                updateSelectionHighlight(traitCollection: traitCollection)
                return
            }
        }
    }

    private func configure() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        clipsToBounds = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        addSubview(stackView)

        for item in options {
            let label = UILabel()
            label.text = item.emoji
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 31)
            label.layer.cornerRadius = 16
            label.layer.cornerCurve = .continuous
            label.clipsToBounds = true
            label.accessibilityLabel = item.name
            optionLabels.append(label)
            stackView.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    private func updateSelectionHighlight(traitCollection: UITraitCollection) {
        for (index, label) in optionLabels.enumerated() {
            label.backgroundColor = index == selectedIndex
                ? KeyboardTheme.emojiCellHighlightColor(for: traitCollection)
                : .clear
        }
    }
}
