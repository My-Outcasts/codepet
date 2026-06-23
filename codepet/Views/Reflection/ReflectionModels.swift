import Foundation

// MARK: - Sources

enum EventSource: String, Codable, CaseIterable {
    case cursorChat = "Cursor chat"
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case manualLog = "Manual log"
}

// MARK: - Triggers

struct TriggerTag: Hashable, Identifiable {
    var id: String { code }
    let code: String          // "T1"
    let label: String         // "Scope creep"
    let confidence: Double    // 0.0 – 1.0
}

// MARK: - Events

struct CapturedEvent: Identifiable, Hashable {
    let id: UUID
    let time: String          // "14:15"
    let isoTime: String       // full ISO 8601 — used for turn_id derivation
    let source: EventSource
    let text: String          // user's prompt (cursor chat) or AI action (claude code)
    let aiSummary: String?    // short summary of AI's response — only populated for cursor chat
    let trigger: TriggerTag?
    let context: String?      // pet's narrative observation — shown on expand
    let isManualLog: Bool
    let sessionId: String?    // Claude Code session that produced this event
    let cwd: String?          // working directory — used for project detection
    let path: String?         // file path context from the event

    init(
        id: UUID = UUID(),
        time: String,
        isoTime: String = "",
        source: EventSource,
        text: String,
        aiSummary: String? = nil,
        trigger: TriggerTag? = nil,
        context: String? = nil,
        isManualLog: Bool = false,
        sessionId: String? = nil,
        cwd: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.time = time
        self.isoTime = isoTime
        self.source = source
        self.text = text
        self.aiSummary = aiSummary
        self.trigger = trigger
        self.context = context
        self.isManualLog = isManualLog
        self.sessionId = sessionId
        self.cwd = cwd
        self.path = path
    }
}

// MARK: - Mood

enum PetMood: String {
    case calm, engaged, alert

    static func derive(risks: Int, decisions: Int) -> PetMood {
        if risks >= 2 { return .alert }
        if decisions >= 3 { return .engaged }
        return .calm
    }

    var label: String {
        switch self {
        case .calm: return "Calm"
        case .engaged: return "Engaged"
        case .alert: return "Alert"
        }
    }
}

// MARK: - Pet name fallback

enum ReflectionPet {
    static let name = "Nova"
    static let initial = "N"
}
