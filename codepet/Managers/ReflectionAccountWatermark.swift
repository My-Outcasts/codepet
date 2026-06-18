import Foundation

/// Per-account "reflection start" watermark, stored in a file under `~/.codepet`
/// so it survives the UserDefaults domain wipe that runs on account switch.
///
/// The reflection logs in `~/.codepet` (events.jsonl, narratives.jsonl, …) are
/// machine-global: they're written by Claude Code hooks that have no idea which
/// CodePet account is signed in. To keep each account's reflection journal
/// isolated, we record the moment each account first signs in on this Mac and
/// hide any coding session that predates it.
enum ReflectionAccountWatermark {

    private static let fileURL: URL = RealHome.url
        .appendingPathComponent(".codepet/account-reflection.json")

    /// uid → start epoch (timeIntervalSince1970)
    private static func load() -> [String: Double] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func save(_ map: [String: Double]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }

    /// The recorded start for an account, or nil if never seen on this Mac.
    static func start(forUID uid: String) -> Date? {
        guard let t = load()[uid] else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// Returns the account's start, recording `fallback` (and persisting it) the
    /// first time the account is seen. Stable across launches afterwards.
    @discardableResult
    static func ensureStart(forUID uid: String, fallback: Date) -> Date {
        var map = load()
        if let t = map[uid] { return Date(timeIntervalSince1970: t) }
        map[uid] = fallback.timeIntervalSince1970
        save(map)
        return fallback
    }

    /// Force-set a specific account's watermark — used to grandfather a primary
    /// account to its full history (`.distantPast`).
    static func record(forUID uid: String, date: Date) {
        var map = load()
        map[uid] = date.timeIntervalSince1970
        save(map)
    }
}
