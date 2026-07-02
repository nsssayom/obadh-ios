import XCTest
@testable import ObadhKeyboardCore

final class PersonalAutosuggestStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testSnapshotPersistsThroughFallbackBaseURL() {
        let store = PersonalAutosuggestStore(
            appGroupIdentifier: nil,
            fallbackBaseURL: temporaryDirectory
        )
        let snapshot = Data([0x0B, 0xAD, 0x06])

        store.saveSnapshot(snapshot)

        XCTAssertEqual(store.loadSnapshot(), snapshot)
    }

    func testRemoveSnapshotDeletesPersistedState() {
        let store = PersonalAutosuggestStore(
            appGroupIdentifier: nil,
            fallbackBaseURL: temporaryDirectory
        )

        store.saveSnapshot(Data([1, 2, 3]))
        store.removeSnapshot()

        XCTAssertNil(store.loadSnapshot())
    }
}
