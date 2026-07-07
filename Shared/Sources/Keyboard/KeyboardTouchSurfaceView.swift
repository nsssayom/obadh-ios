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

    /// Touches with y above this (the suggestion bar) are passed through so the
    /// suggestion bar beneath receives them. Below it, the surface resolves keys.
    /// Lets the surface be full-bleed (uniform, no rectangle) while only owning
    /// the key area.
    var keyAreaTop: CGFloat = 0

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

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, !keyRows.isEmpty else {
            return false
        }
        return point.y >= keyAreaTop && bounds.contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, !keyRows.isEmpty else {
            return nil
        }
        return (point.y >= keyAreaTop && bounds.contains(point)) ? self : nil
    }

    private func configure() {
        // CRITICAL: a custom keyboard EXTENSION drops touches over regions where
        // the touch-receiving view renders fully transparent (verified on-device
        // + on-sim; the system keyboard is exempt because it isn't an extension).
        // A visual-effect glass backdrop behind does NOT count — only a plain,
        // non-transparent background on THIS view makes the inter-key gaps
        // touchable. ~1/255 alpha: the system registers the color so touches
        // land, but it is genuinely imperceptible (0.02 was ~5x too high and
        // read as a tint). Do NOT set to `.clear`.
        // Ref: https://developer.apple.com/forums/thread/702798
        backgroundColor = UIColor.white.withAlphaComponent(0.004)
        isOpaque = false
        isUserInteractionEnabled = true
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
