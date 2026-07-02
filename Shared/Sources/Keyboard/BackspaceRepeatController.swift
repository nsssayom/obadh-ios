import Foundation

final class BackspaceRepeatController: NSObject {
    private let policy: BackspaceRepeatPolicy
    private var timer: Timer?
    private var startedAt: Date?
    private var lastFireAt: Date?
    private var action: ((BackspaceDeletionUnit) -> Void)?

    init(policy: BackspaceRepeatPolicy = .nativeLike) {
        self.policy = policy
        super.init()
    }

    var isActive: Bool {
        timer != nil
    }

    func begin(action: @escaping (BackspaceDeletionUnit) -> Void) {
        guard !isActive else { return }

        let now = Date()
        startedAt = now
        lastFireAt = now
        self.action = action

        timer = Timer.scheduledTimer(
            timeInterval: 0.03,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func end() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        lastFireAt = nil
        action = nil
    }

    @objc private func timerFired(_ timer: Timer) {
        tick()
    }

    private func tick() {
        guard let startedAt, let lastFireAt, let action else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        guard let stage = policy.stage(elapsed: elapsed) else { return }
        guard now.timeIntervalSince(lastFireAt) >= stage.interval else { return }

        self.lastFireAt = now
        action(stage.unit)
    }
}
