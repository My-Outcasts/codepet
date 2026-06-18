import Foundation
import Combine
import FirebaseFirestore

// MARK: - MCP Bridge Models

/// Mirrors the DailySummary from the MCP server's session-logger.ts
struct MCPDailySummary: Codable {
    let date: String
    let totalCodingMinutes: Int
    let linesAdded: Int
    let linesRemoved: Int
    let commits: Int
    let aiSessions: Int
    let errorsFixed: Int
    let languageBreakdown: [String: Int]
    let skillsTracked: [String: Int]
    let topFiles: [String]
    let petReaction: String?
}

/// Mirrors SkillProgress from the MCP server's skill-map.ts
struct MCPSkillProgress: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let kingdom: String
    let tier: Int
    let nodeType: String
    let xp: Int
    let level: Int
    let maxLevel: Int
    let xpProgress: Int
    let xpToNextLevel: Int
}

/// Mirrors StoredEvent from the MCP server's session-logger.ts
struct MCPSessionEvent: Codable, Identifiable {
    let id: Int
    let timestamp: String
    let type: String
    let action: String
    let project: String?
    let language: String?
    let file: String?
}

// MARK: - MCP Bridge Service

/// Reads data from ~/.codepet/ (written by the MCP server) and exposes it to SwiftUI.
/// Polls every 30 seconds for updates.
class MCPBridgeService: ObservableObject {
    static let shared = MCPBridgeService()

    private let codepetDir: URL
    private var refreshTimer: Timer?
    // Lazy so the singleton can be created without spinning up Firestore (which
    // aborts under the test runner). All access goes through loadFromFirestore,
    // which is itself test-guarded.
    private lazy var db = Firestore.firestore()

    @Published var todaySummary: MCPDailySummary?
    @Published var skillProgress: [MCPSkillProgress] = []
    @Published var todayEvents: [MCPSessionEvent] = []
    @Published var isConnected: Bool = false
    /// True when the data comes from the Cursor extension via Firestore (not local MCP files)
    @Published var dataSource: String = "none" // "local", "extension", "none"

    /// Total XP earned from real coding activity (across all skills)
    var totalSkillXP: Int {
        skillProgress.reduce(0) { $0 + $1.xp }
    }

    /// Number of active days in events directory
    @Published var activeDaysCount: Int = 0

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        codepetDir = home.appendingPathComponent(".codepet")
        refresh()
        startPolling()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Data Loading

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let connected = fm.fileExists(atPath: self.codepetDir.path)

            // Try local MCP files first
            let summary = connected ? self.readTodaySummary() : nil
            let events = connected ? self.readTodayEvents() : []
            let skills = connected ? self.readSkillProgress() : []
            let days = connected ? self.readActiveDays() : 0

            DispatchQueue.main.async {
                let hasLocalData = summary != nil && (summary?.totalCodingMinutes ?? 0) > 0
                self.isConnected = connected || self.dataSource == "extension"

                if hasLocalData {
                    // Local MCP data available — use it
                    self.dataSource = "local"
                    if !Self.summariesEqual(self.todaySummary, summary) { self.todaySummary = summary }
                } else {
                    // No local data for today — poll Firestore for extension data
                    // (polls every 30s so the dashboard updates as you code in Cursor)
                    self.loadFromFirestore()
                }

                if self.skillProgress.map(\.id) != skills.map(\.id) || self.skillProgress.map(\.xp) != skills.map(\.xp) {
                    self.skillProgress = skills
                }
                if self.todayEvents.count != events.count { self.todayEvents = events }
                if self.activeDaysCount != days { self.activeDaysCount = days }
            }
        }
    }

    /// Load today's coding data from Firestore (written by the Cursor extension)
    private func loadFromFirestore() {
        guard !AppEnvironment.isRunningTests else { return }
        // Read UID from UserDefaults
        let defaults = UserDefaults.standard
        guard let uid = defaults.string(forKey: "cp_currentUserId"), !uid.isEmpty else {
            print("[MCPBridge] No user ID for Firestore lookup")
            return
        }

        // The Cursor extension writes to: users/{uid}/extensions/cursor
        let docPath = "users/\(uid)/extensions/cursor"
        db.document(docPath).getDocument { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else {
                if let error = error {
                    print("[MCPBridge] Firestore error: \(error.localizedDescription)")
                }
                return
            }

            // Extract session data from the Firestore document
            let session = data["session"] as? [String: Any] ?? [:]
            let scanner = data["scanner"] as? [String: Any] ?? [:]

            // Helper: Firestore numbers may come back as Int, Int64, Double, or NSNumber
            func intVal(_ dict: [String: Any], _ key: String) -> Int {
                if let v = dict[key] as? Int { return v }
                if let v = dict[key] as? Int64 { return Int(v) }
                if let v = dict[key] as? Double { return Int(v) }
                if let v = dict[key] as? NSNumber { return v.intValue }
                return 0
            }

            let codingMinutes = intVal(session, "codingMinutes")
            guard codingMinutes > 0 else { return } // Don't show empty data

            let linesAdded = intVal(session, "linesAdded")
            let linesRemoved = intVal(session, "linesRemoved")
            let totalEdits = intVal(session, "totalEdits")
            let filesEdited = intVal(session, "filesEdited")
            let topLanguage = session["topLanguage"] as? String ?? ""
            let errorsFixed = intVal(scanner, "totalErrors")

            // Language breakdown — handle Firestore number types
            var langBreakdown: [String: Int] = [:]
            if let rawLangs = session["languageBreakdown"] as? [String: Any] {
                for (lang, val) in rawLangs {
                    langBreakdown[lang] = intVal(rawLangs, lang)
                }
            }

            // Generate a pet reaction based on coding activity
            let petReaction: String?
            if codingMinutes >= 120 {
                petReaction = "You're on fire today! Keep going!"
            } else if codingMinutes >= 60 {
                petReaction = "Great coding session! You're building something amazing!"
            } else if codingMinutes >= 30 {
                petReaction = "Nice progress! Keep the momentum going!"
            } else {
                petReaction = "Let's code together!"
            }

            let summary = MCPDailySummary(
                date: self.todayString(),
                totalCodingMinutes: codingMinutes,
                linesAdded: linesAdded,
                linesRemoved: linesRemoved,
                commits: totalEdits,  // use edits as proxy for commits
                aiSessions: filesEdited,
                errorsFixed: errorsFixed,
                languageBreakdown: langBreakdown,
                skillsTracked: [:],
                topFiles: [],
                petReaction: petReaction
            )

            DispatchQueue.main.async {
                self.dataSource = "extension"
                self.isConnected = true
                if !Self.summariesEqual(self.todaySummary, summary) {
                    self.todaySummary = summary
                    print("[MCPBridge] Loaded extension data from Firestore: \(codingMinutes)m, +\(linesAdded) lines")
                }
            }
        }
    }

    private static func summariesEqual(_ a: MCPDailySummary?, _ b: MCPDailySummary?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?):
            return a.date == b.date
                && a.totalCodingMinutes == b.totalCodingMinutes
                && a.linesAdded == b.linesAdded
                && a.linesRemoved == b.linesRemoved
                && a.commits == b.commits
                && a.errorsFixed == b.errorsFixed
                && a.aiSessions == b.aiSessions
        }
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func readTodaySummary() -> MCPDailySummary? {
        let path = codepetDir
            .appendingPathComponent("summaries")
            .appendingPathComponent("\(todayString()).json")

        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(MCPDailySummary.self, from: data)
    }

    private func readTodayEvents() -> [MCPSessionEvent] {
        let path = codepetDir
            .appendingPathComponent("events")
            .appendingPathComponent("\(todayString()).json")

        guard let data = try? Data(contentsOf: path) else { return [] }
        return (try? JSONDecoder().decode([MCPSessionEvent].self, from: data)) ?? []
    }

    private func readSkillProgress() -> [MCPSkillProgress] {
        let profilePath = codepetDir.appendingPathComponent("profile.json")

        guard let data = try? Data(contentsOf: profilePath),
              let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skillData = profile["skill_progress"],
              let skillJSON = try? JSONSerialization.data(withJSONObject: skillData) else {
            return []
        }

        return (try? JSONDecoder().decode([MCPSkillProgress].self, from: skillJSON)) ?? []
    }

    private func readActiveDays() -> Int {
        let eventsDir = codepetDir.appendingPathComponent("events")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: eventsDir.path) else { return 0 }
        return files.filter { $0.hasSuffix(".json") }.count
    }
}
