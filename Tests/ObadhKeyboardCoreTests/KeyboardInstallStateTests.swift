import Foundation
import XCTest
@testable import ObadhKeyboardCore

final class KeyboardInstallStateTests: XCTestCase {
    private var globalSuite: String!
    private var sharedSuite: String!
    private var globalDefaults: UserDefaults!
    private var sharedDefaults: UserDefaults!

    private let obadh = KeyboardInstallStateReader.keyboardBundleIdentifier

    override func setUp() {
        super.setUp()
        globalSuite = "KeyboardInstallStateTests.global.\(UUID().uuidString)"
        sharedSuite = "KeyboardInstallStateTests.shared.\(UUID().uuidString)"
        globalDefaults = UserDefaults(suiteName: globalSuite)
        sharedDefaults = UserDefaults(suiteName: sharedSuite)
        globalDefaults.removePersistentDomain(forName: globalSuite)
        sharedDefaults.removePersistentDomain(forName: sharedSuite)
    }

    override func tearDown() {
        globalDefaults.removePersistentDomain(forName: globalSuite)
        sharedDefaults.removePersistentDomain(forName: sharedSuite)
        globalDefaults = nil
        sharedDefaults = nil
        super.tearDown()
    }

    private func read() -> KeyboardInstallState {
        KeyboardInstallStateReader(
            globalDefaults: globalDefaults,
            sharedDefaults: sharedDefaults
        ).read()
    }

    private func setEnabledKeyboards(_ values: [String]) {
        globalDefaults.set(values, forKey: "AppleKeyboards")
    }

    /// The shape iOS actually writes, captured from a live device's global domain.
    func testDetectsObadhAmongSystemKeyboards() {
        setEnabledKeyboards([
            "en_US@sw=QWERTY;hw=Automatic",
            obadh,
            "emoji@sw=Emoji",
            "bn-Translit@sw=QWERTY-Bengali;hw=Automatic"
        ])

        XCTAssertTrue(read().isKeyboardInstalled)
    }

    func testAbsentFromKeyboardListReadsAsNotInstalled() {
        setEnabledKeyboards(["en_US@sw=QWERTY;hw=Automatic", "emoji@sw=Emoji"])

        XCTAssertFalse(read().isKeyboardInstalled)
    }

    /// A missing key must read as "not installed", not crash or report installed.
    func testMissingKeyboardListReadsAsNotInstalled() {
        XCTAssertFalse(read().isKeyboardInstalled)
    }

    /// Guards against a substring match reporting a different vendor's keyboard.
    func testDoesNotMatchAnUnrelatedKeyboardSharingOurPrefix() {
        setEnabledKeyboards(["com.nsssayom.obadh.keyboard.evil", "com.example.obadh.keyboard"])

        XCTAssertFalse(read().isKeyboardInstalled)
    }

    /// iOS may append a suffix to the bare identifier; both shapes must match.
    func testMatchesSuffixedIdentifier() {
        setEnabledKeyboards(["\(obadh)@sw=QWERTY"])

        XCTAssertTrue(read().isKeyboardInstalled)
    }

    /// The stamp can only exist if the extension reached the shared container, which
    /// requires Full Access. Presence is proof.
    func testFullAccessConfirmedOnlyWhenTheExtensionStampedTheSharedContainer() {
        XCTAssertFalse(read().isFullAccessConfirmed)

        KeyboardPreferences(defaults: sharedDefaults).fullAccessConfirmedAt = Date()

        XCTAssertTrue(read().isFullAccessConfirmed)
    }

    /// Install state and Full Access are independent signals.
    func testFullAccessIsIndependentOfInstallation() {
        KeyboardPreferences(defaults: sharedDefaults).fullAccessConfirmedAt = Date()

        let state = read()
        XCTAssertFalse(state.isKeyboardInstalled)
        XCTAssertTrue(state.isFullAccessConfirmed)
    }
}
