import UIKit

final class KeyboardTouchCellControl: UIControl {
    let keyButton: KeyboardKeyButton

    init(keyButton: KeyboardKeyButton) {
        self.keyButton = keyButton
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            keyButton.isHighlighted = isHighlighted
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = true
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        isHighlighted = bounds.insetBy(dx: -8, dy: -8).contains(location)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isHighlighted = false
    }

    override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = true
    }
}
