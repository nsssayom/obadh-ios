import UIKit

@MainActor
protocol KeyboardTouchSurfaceViewDelegate: AnyObject {
    func keyboardTouchSurface(_ view: KeyboardTouchSurfaceView, didBegin key: KeyboardKey)
    func keyboardTouchSurface(_ view: KeyboardTouchSurfaceView, didMoveTo key: KeyboardKey)
    func keyboardTouchSurface(_ view: KeyboardTouchSurfaceView, didEnd key: KeyboardKey?)
    func keyboardTouchSurfaceDidCancel(_ view: KeyboardTouchSurfaceView)
}

final class KeyboardTouchSurfaceView: UIView {
    weak var delegate: KeyboardTouchSurfaceViewDelegate?

    var keyRows: [[KeyboardTouchKeyRegion]] = [] {
        didSet {
            activeRegion = activeTouch.flatMap { resolve($0.location(in: self)) }
        }
    }

    private weak var activeTouch: UITouch?
    private var activeRegion: KeyboardTouchResolvedRegion?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        guard let region = resolve(touch.location(in: self)) else {
            activeRegion = nil
            return
        }
        activeRegion = region
        delegate?.keyboardTouchSurface(self, didBegin: region.key)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touch(from: touches) else { return }
        let region = resolve(touch.location(in: self))
        guard region?.key != activeRegion?.key else { return }
        activeRegion = region
        if let region {
            delegate?.keyboardTouchSurface(self, didMoveTo: region.key)
        } else {
            delegate?.keyboardTouchSurfaceDidCancel(self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touch(from: touches) else { return }
        let region = resolve(touch.location(in: self)) ?? activeRegion
        activeTouch = nil
        activeRegion = nil
        delegate?.keyboardTouchSurface(self, didEnd: region?.key)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch(from: touches) != nil else { return }
        activeTouch = nil
        activeRegion = nil
        delegate?.keyboardTouchSurfaceDidCancel(self)
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityViewIsModal = false
    }

    private func touch(from touches: Set<UITouch>) -> UITouch? {
        guard let activeTouch else { return nil }
        return touches.first { $0 === activeTouch }
    }

    private func resolve(_ point: CGPoint) -> KeyboardTouchResolvedRegion? {
        KeyboardTouchResolver.resolve(
            point: point,
            rows: keyRows,
            bounds: bounds
        )
    }
}
