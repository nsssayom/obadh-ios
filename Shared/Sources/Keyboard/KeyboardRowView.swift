import UIKit

final class KeyboardRowView: UIView {
    var metrics = KeyboardTheme.defaultMetrics {
        didSet {
            setNeedsLayout()
        }
    }
    var touchInsets: UIEdgeInsets = .zero {
        didSet {
            setNeedsLayout()
        }
    }

    private var row: KeyboardRow?
    private var keyButtons: [KeyboardKeyButton] = []
    private var touchCells: [KeyboardTouchCellControl] = []

    func configure(row: KeyboardRow, buttons: [KeyboardKeyButton], metrics: KeyboardMetrics) {
        touchCells.forEach { $0.removeFromSuperview() }
        keyButtons.forEach { $0.removeFromSuperview() }
        self.row = row
        self.keyButtons = buttons
        self.touchCells = buttons.map { KeyboardTouchCellControl(keyButton: $0) }
        self.metrics = metrics

        for button in buttons {
            button.isUserInteractionEnabled = false
            addSubview(button)
        }
        for touchCell in touchCells {
            addSubview(touchCell)
        }
        setNeedsLayout()
    }

    func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
        for touchCell in touchCells {
            touchCell.addTarget(target, action: action, for: controlEvents)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let row else { return }

        let contentBounds = bounds.inset(by: UIEdgeInsets(
            top: 0,
            left: metrics.keyboardInsets.left,
            bottom: 0,
            right: metrics.keyboardInsets.right
        ))
        let frames = KeyboardLayoutGeometry.keyFrames(
            for: row,
            availableWidth: contentBounds.width,
            keySpacing: Double(metrics.keySpacing)
        )
        guard frames.count == keyButtons.count, frames.count == touchCells.count else { return }

        let scale = window?.screen.scale ?? UIScreen.main.scale
        var visualFrames: [CGRect] = []
        visualFrames.reserveCapacity(frames.count)
        for (index, frame) in frames.enumerated() {
            let minX = align(contentBounds.minX + CGFloat(frame.x), scale: scale)
            let maxX = align(contentBounds.minX + CGFloat(frame.x + frame.width), scale: scale)
            let visualFrame = CGRect(
                x: minX,
                y: 0,
                width: max(0, maxX - minX),
                height: bounds.height
            )
            keyButtons[index].frame = visualFrame
            visualFrames.append(visualFrame)
        }

        let touchReferenceFrames = frames.map { frame in
            KeyboardKeyFrame(
                key: frame.key,
                x: Double(contentBounds.minX) + frame.x,
                width: frame.width
            )
        }
        let cellFrames = KeyboardTouchCellGeometry.cellFrames(
            for: touchReferenceFrames,
            availableWidth: Double(bounds.width),
            rowHeight: Double(bounds.height),
            topInset: Double(touchInsets.top),
            bottomInset: Double(touchInsets.bottom)
        )
        guard cellFrames.count == touchCells.count else { return }

        for (index, frame) in cellFrames.enumerated() {
            let minX = align(CGFloat(frame.x), scale: scale)
            let maxX = align(CGFloat(frame.maxX), scale: scale)
            let minY = align(CGFloat(frame.y), scale: scale)
            let maxY = align(CGFloat(frame.y + frame.height), scale: scale)
            touchCells[index].frame = CGRect(
                x: minX,
                y: minY,
                width: max(0, maxX - minX),
                height: max(0, maxY - minY)
            )
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        touchBounds.contains(point)
    }

    private func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private var touchBounds: CGRect {
        CGRect(
            x: 0,
            y: -touchInsets.top,
            width: bounds.width,
            height: bounds.height + touchInsets.top + touchInsets.bottom
        )
    }
}
