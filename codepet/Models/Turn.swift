import Foundation

struct SessionSummary: Codable, Hashable {
    let sessionId: String
    let summary: String       // ≤500 chars — narrative arc of the session
    let lesson: String        // ≤300 chars — overarching takeaway
    let generatedAt: Date
    let model: String
    let schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case summary
        case lesson
        case generatedAt = "generated_at"
        case model
        case schemaVersion = "schema_version"
    }
}

/// Session = N turns + optional summary. Pure aggregation, no I/O.
struct Session: Identifiable, Hashable {
    let id: String              // sessionId
    let turns: [Turn]           // sorted oldest-first (chronological reading)
    let startedAt: Date
    let endedAt: Date?
    let summary: SessionSummary?
    let projectPath: String?    // inferred from cwd of first event — used for project grouping
    let filePaths: [String]     // file paths from tool events — helps disambiguate multi-project workspaces
}

extension Session {
    static let welcomeSessionId = "welcome-onboarding"
    var isWelcome: Bool { id == Self.welcomeSessionId }

    /// True when at least one turn contains write operations (file edits,
    /// file writes, or non-trivial bash commands). Sessions where the user
    /// only ran read-only commands (git status, ls, cat) or got text-only
    /// replies have no meaningful work to narrate.
    var hasMeaningfulWork: Bool {
        turns.contains { $0.hasWriteEvents }
    }

    static func makeWelcome() -> Session {
        Session(
            id: welcomeSessionId,
            turns: [],
            startedAt: Date(),
            endedAt: nil,
            summary: nil,
            projectPath: nil,
            filePaths: []
        )
    }
}

/// A skill detected by the AI during a coding session.
struct DetectedSkill: Codable, Hashable {
    let skillId: String        // e.g. "component_composition"
    let confidence: String     // "strong" | "weak"
    let evidence: String       // one-sentence explanation

    enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case confidence, evidence
    }
}

struct Narrative: Codable, Hashable {
    let title: String
    let whatYouWanted: String
    let whatHappened: String
    let lesson: String
    let nextSteps: String
    let mood: String
    let detectedSkills: [DetectedSkill]
    let model: String
    let generatedAt: Date
    let schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case title
        case whatYouWanted = "what_you_wanted"
        case whatHappened = "what_happened"
        case lesson
        case nextSteps = "next_steps"
        case mood
        case detectedSkills = "detected_skills"
        case model
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
    }

    init(
        title: String,
        whatYouWanted: String,
        whatHappened: String,
        lesson: String,
        nextSteps: String = "",
        mood: String = "idle",
        detectedSkills: [DetectedSkill] = [],
        model: String,
        generatedAt: Date,
        schemaVersion: Int
    ) {
        self.title = title
        self.whatYouWanted = whatYouWanted
        self.whatHappened = whatHappened
        self.lesson = lesson
        self.nextSteps = nextSteps
        self.mood = mood
        self.detectedSkills = detectedSkills
        self.model = model
        self.generatedAt = generatedAt
        self.schemaVersion = schemaVersion
    }

    /// Backward-compatible decoder.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        whatYouWanted = try c.decode(String.self, forKey: .whatYouWanted)
        whatHappened = try c.decode(String.self, forKey: .whatHappened)
        lesson = try c.decode(String.self, forKey: .lesson)
        nextSteps = try c.decodeIfPresent(String.self, forKey: .nextSteps) ?? ""
        mood = try c.decodeIfPresent(String.self, forKey: .mood) ?? "idle"
        detectedSkills = try c.decodeIfPresent([DetectedSkill].self, forKey: .detectedSkills) ?? []
        model = try c.decode(String.self, forKey: .model)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    }
}

enum FailureReason: String, Codable, Hashable {
    case network
    case auth
    case quota
    case badResponse = "bad_response"
    case unknown
}

enum TurnState: Hashable {
    case pending           // no Stop event yet
    case summarizing       // API call in flight
    case ready             // narrative present
    case failed(reason: FailureReason)
    case pendingOrphan     // no Stop event after 30 min
}

struct Turn: Identifiable, Hashable {
    let id: String              // turn_id
    let sessionId: String
    let startedAt: Date
    let endedAt: Date?
    let prompt: String
    let rawEvents: [CapturedEvent]
    let narrative: Narrative?
    let state: TurnState
    let cwd: String?            // working directory from the prompt event — available immediately

    /// True when the turn contains at least one write operation (Edit, Write,
    /// or a non-trivial Bash command). Read-only commands like `git log`,
    /// `git status`, `ls`, `cat` don't count as meaningful work.
    var hasWriteEvents: Bool {
        rawEvents.contains { event in
            let text = event.text.trimmingCharacters(in: .whitespaces)
            // Edit and Write are always write operations
            if text.hasPrefix("Edit") || text.hasPrefix("Write") { return true }
            // Bash commands: check if they're read-only
            if text.hasPrefix("Bash:") || text.hasPrefix("Bash(") {
                return !Self.isReadOnlyBash(text)
            }
            // Other tool types (e.g. Read, Glob, Grep) are read-only
            return false
        }
    }

    /// Returns true if a Bash event text represents a read-only command.
    /// Handles compound commands (`cmd1 && cmd2`) by checking each sub-command.
    /// Internal visibility so TurnAssembler can reuse the same logic.
    static func isReadOnlyBash(_ text: String) -> Bool {
        // Extract the actual command after "Bash:" or "Bash("
        let cmd = text
            .replacingOccurrences(of: "Bash:", with: "")
            .replacingOccurrences(of: "Bash(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        let readOnlyPrefixes = [
            "git log", "git status", "git diff", "git show", "git branch",
            "git remote", "git tag", "git stash list",
            "ls", "cat", "head", "tail", "find", "grep", "rg",
            "wc", "file", "stat", "pwd", "echo", "which", "whoami",
            "tree", "du", "df"
        ]

        // Split compound commands on && and || and check each part
        let subCommands = cmd
            .replacingOccurrences(of: "||", with: "&&")
            .components(separatedBy: "&&")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !subCommands.isEmpty else { return true }
        return subCommands.allSatisfy { sub in
            readOnlyPrefixes.contains { sub.hasPrefix($0) }
        }
    }

    static func makeID(sessionId: String, promptISO: String) -> String {
        "\(sessionId):\(promptISO)"
    }
}

#if DEBUG
extension Turn {
    /// Convenience factory for unit tests. Fills required fields with neutral defaults.
    static func makeForTesting(
        id: String = "test-turn-id",
        sessionId: String = "test-session",
        prompt: String,
        startedAt: Date,
        endedAt: Date?,
        narrative: Narrative?,
        rawEvents: [CapturedEvent],
        cwd: String? = nil
    ) -> Turn {
        Turn(
            id: id,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            prompt: prompt,
            rawEvents: rawEvents,
            narrative: narrative,
            state: .ready,
            cwd: cwd
        )
    }
}

extension Session {
    /// Convenience factory for unit tests.
    static func makeForTesting(
        id: String,
        startedAt: Date,
        endedAt: Date?,
        turns: [Turn],
        summary: SessionSummary?,
        projectPath: String? = nil,
        filePaths: [String] = []
    ) -> Session {
        Session(
            id: id,
            turns: turns,
            startedAt: startedAt,
            endedAt: endedAt,
            summary: summary,
            projectPath: projectPath,
            filePaths: filePaths
        )
    }
}

extension SessionSummary {
    /// Convenience factory for unit tests that mirrors the test call-site signature.
    static func makeForTesting(
        sessionId: String,
        summary: String,
        lesson: String,
        createdAt: Date
    ) -> SessionSummary {
        SessionSummary(
            sessionId: sessionId,
            summary: summary,
            lesson: lesson,
            generatedAt: createdAt,
            model: "test-model",
            schemaVersion: 1
        )
    }
}
#endif
