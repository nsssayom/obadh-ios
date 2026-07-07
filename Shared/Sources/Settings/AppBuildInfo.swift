import Foundation

/// Build identity read from the bundle's Info.plist. In the app this reflects the
/// app bundle; in the keyboard extension it reflects the extension bundle — so
/// comparing the two confirms both halves are the same build (and that the
/// extension isn't serving a cached old binary). Values are stamped per build by
/// `scripts/stamp-build.sh` via Config/BuildInfo.xcconfig.
enum AppBuildInfo {
    /// Marketing version, e.g. "0.1.0" (CFBundleShortVersionString).
    static var shortVersion: String { string("CFBundleShortVersionString") }
    /// Build number — the git commit count, e.g. "8" (CFBundleVersion).
    static var buildNumber: String { string("CFBundleVersion") }
    /// Short git SHA, with "-dirty" when built from an uncommitted tree.
    static var gitRevision: String { string("OBADHGitRevision") }
    /// UTC build timestamp, e.g. "2026-07-06.2015".
    static var buildTime: String { string("OBADHBuildTime") }

    /// One-line summary, e.g. "0.1.0 (8) · eacc924a-dirty · 2026-07-06.2015".
    static var summary: String {
        var parts = ["\(shortVersion) (\(buildNumber))"]
        if !gitRevision.isEmpty { parts.append(gitRevision) }
        if !buildTime.isEmpty { parts.append(buildTime) }
        return parts.joined(separator: " · ")
    }

    private static func string(_ key: String) -> String {
        (Bundle.main.infoDictionary?[key] as? String) ?? ""
    }
}
