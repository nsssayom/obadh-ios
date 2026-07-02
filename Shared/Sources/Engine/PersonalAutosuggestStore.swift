import Foundation

struct PersonalAutosuggestStore {
    private let fileManager: FileManager
    private let appGroupIdentifier: String?
    private let fallbackBaseURL: URL?

    init(
        fileManager: FileManager = .default,
        appGroupIdentifier: String? = KeyboardPreferences.appGroupIdentifier,
        fallbackBaseURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appGroupIdentifier = appGroupIdentifier
        self.fallbackBaseURL = fallbackBaseURL
    }

    func loadSnapshot() -> Data? {
        guard let url = snapshotURL else {
            return nil
        }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    func saveSnapshot(_ data: Data) {
        guard !data.isEmpty, let url = snapshotURL else {
            return
        }
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    func removeSnapshot() {
        guard let url = snapshotURL, fileManager.fileExists(atPath: url.path) else {
            return
        }
        try? fileManager.removeItem(at: url)
    }

    private var snapshotURL: URL? {
        guard let baseURL = sharedBaseURL else {
            return nil
        }
        return baseURL
            .appendingPathComponent("ObadhKeyboard", isDirectory: true)
            .appendingPathComponent("personal-autosuggest.snapshot", isDirectory: false)
    }

    private var sharedBaseURL: URL? {
        if let appGroupIdentifier,
           let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        }

        if let fallbackBaseURL {
            return fallbackBaseURL
        }

        return fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    }
}
