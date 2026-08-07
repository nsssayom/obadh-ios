import Foundation
import Testing

private final class ContentionBundleToken {}

/// Guards the property that makes typing responsive on non-flagship hardware: the
/// keystroke path must not be blocked by background suggestion work.
///
/// `transliterate` runs on the main thread for every keypress and costs ~0.001 ms.
/// `compositionSuggestions` runs on a background queue and costs 1.3-5.3 ms against
/// the real `bn.fst` (measured on Mac; several times that on a phone). They touch
/// different engine handles, so they must not contend. When both shared one lock,
/// each keystroke queued behind milliseconds of unrelated FST traversal — which fit
/// between keystrokes on an A18 Pro but not on an A18, where the backlog and the
/// visible latency grew without bound while typing.
///
/// If this test starts failing, someone has reintroduced a shared lock.
@Suite(.serialized)
struct EngineContentionTests {
    let engine = ObadhBridgeClient.shared

    init() {
        _ = ObadhBridgeClient.shared.configureModels(in: Bundle(for: ContentionBundleToken.self))
    }

    @Test func transliterationIsNotBlockedByBackgroundSuggestionWork() async throws {
        let deadline = Date().addingTimeInterval(1.0)
        let load = Thread {
            // Long prefixes: the deepest, most expensive FST traversals.
            let inputs = ["banglad", "bangladesh", "bangl", "shomporko", "bishwabidyalay"]
            var i = 0
            while Date() < deadline {
                _ = ObadhBridgeClient.shared.compositionSuggestions(for: inputs[i % inputs.count], limit: 4)
                i += 1
            }
        }
        load.qualityOfService = .userInitiated
        load.start()

        // Let the background thread get inside the FST before sampling.
        try await Task.sleep(for: .milliseconds(50))

        var samples: [Double] = []
        while Date() < deadline {
            let t0 = Date()
            _ = engine.transliterate("bangla")
            samples.append(Date().timeIntervalSince(t0) * 1000)
        }

        // Starvation shows up here first: with a shared lock this loop completed only
        // TWO transliterations in the same ~1s window, versus hundreds when the
        // keystroke path has its own handle lock.
        try #require(
            samples.count > 50,
            "only \(samples.count) transliterations completed in ~1s — the keystroke path is being starved by background suggestion work"
        )
        let sorted = samples.sorted()
        let p90 = sorted[Int(Double(sorted.count) * 0.90)]

        // Unblocked this is microseconds. Sharing a lock with the FST search put it
        // in the millisecond range, so 1.0 ms separates the two cleanly while leaving
        // ample room for scheduling jitter.
        #expect(p90 < 1.0, "transliterate p90 \(p90) ms under background suggestion load — the keystroke path is contending")
    }
}
