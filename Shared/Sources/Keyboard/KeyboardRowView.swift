import UIKit

final class KeyboardRowView: UIView {
    var metrics = KeyboardTheme.defaultMetrics {
        didSet {
            setNeedsLayout()
        }
    }

    private var row: KeyboardRow?
    private var keyButtons: [KeyboardKeyButton] = []

    func configure(row: KeyboardRow, buttons: [KeyboardKeyButton], metrics: KeyboardMetrics) {
        keyButtons.forEach { $0.removeFromSuperview() }
        self.row = row
        self.keyButtons = buttons
        self.metrics = metrics

        for button in buttons {
            addSubview(button)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let row else { return }

        let frames = KeyboardLayoutGeometry.keyFrames(
            for: row,
            availableWidth: bounds.width,
            keySpacing: Double(metrics.keySpacing)
        )
        guard frames.count == keyButtons.count else { return }

        let scale = window?.screen.scale ?? UIScreen.main.scale
        for (index, frame) in frames.enumerated() {
            let minX = align(CGFloat(frame.x), scale: scale)
            let maxX = align(CGFloat(frame.x + frame.width), scale: scale)
            keyButtons[index].frame = CGRect(
                x: minX,
                y: 0,
                width: max(0, maxX - minX),
                height: bounds.height
            )
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds
            .insetBy(
                dx: -metrics.rowTouchExtension,
                dy: -metrics.rowTouchExtension
            )
            .contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let directHit = super.hitTest(point, with: event)
        if directHit is KeyboardKeyButton {
            return directHit
        }

        guard let nearestButton = nearestButton(to: point) else {
            return directHit
        }
        let pointInButton = convert(point, to: nearestButton)
        let expandedBounds = nearestButton.bounds.insetBy(
            dx: -metrics.keyTouchExtension,
            dy: -metrics.keyTouchExtension
        )
        return expandedBounds.contains(pointInButton) ? nearestButton : directHit
    }

    private func nearestButton(to point: CGPoint) -> KeyboardKeyButton? {
        var nearest: KeyboardKeyButton?
        var nearestDistance = CGFloat.greatestFiniteMagnitude

        for button in keyButtons where button.isUserInteractionEnabled {
            let center = convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
            let dx = center.x - point.x
            let dy = center.y - point.y
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = button
            }
        }

        return nearest
    }

    private func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}
