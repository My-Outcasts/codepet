import Foundation

enum NotificationChannel: String, Codable, CaseIterable {
    case off, inApp
}

/// Everything the founder sets in the settings modal that the model or the notification
/// layer needs to see. Persisted as one field on the company doc so it syncs across
/// machines instead of living in UserDefaults.
/// `Hashable` (not just `Equatable`) because `CompanyState`, which now carries a
/// `FounderPrefs`, is itself `Hashable` — a synthesised conformance needs every stored
/// property to be hashable. `Hashable` refines `Equatable`, so Task 7's equality holds.
struct FounderPrefs: Codable, Hashable {
    var style: AIStyle = .init()
    var memoryEnabled: Bool = true
    /// Category key -> channel. An absent key means that category's default.
    var notifications: [String: NotificationChannel] = [:]

    // Adding init(from:) below suppresses Swift's synthesized no-argument initializer,
    // so it has to be restated explicitly to keep `FounderPrefs()` working.
    init() {}

    // Hand-written so a document written before a future property was added still decodes:
    // Swift's synthesized Decodable calls decode(forKey:), which throws keyNotFound on a
    // missing key instead of falling back to the property's declared default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(AIStyle.self, forKey: .style) ?? .init()
        memoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? true
        notifications = try container.decodeIfPresent([String: NotificationChannel].self, forKey: .notifications) ?? [:]
    }
}

/// How the founder's team talks to them.
///
/// `promptFragment()` is the entire behavioural seam. It returns `nil` when nothing has
/// been changed, so an untouched settings panel adds zero tokens to every request — the
/// property that makes this safe to ship.
/// `Hashable` for the same reason as `FounderPrefs`.
struct AIStyle: Codable, Hashable {
    enum Level: String, Codable, CaseIterable { case less, `default`, more }
    enum BaseTone: String, Codable, CaseIterable {
        case `default`, direct, encouraging, analytical
    }

    var baseTone: BaseTone = .default
    var warmth: Level = .default
    var enthusiasm: Level = .default
    var emoji: Level = .default
    var customInstructions: String = ""
    var role: String = ""
    var moreAboutYou: String = ""

    // Adding init(from:) below suppresses Swift's synthesized no-argument initializer,
    // so it has to be restated explicitly to keep `AIStyle()` working.
    init() {}

    // Hand-written for the same reason as FounderPrefs.init(from:): the synthesized
    // decoder throws keyNotFound on an absent key instead of falling back to the default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseTone = try container.decodeIfPresent(BaseTone.self, forKey: .baseTone) ?? .default
        warmth = try container.decodeIfPresent(Level.self, forKey: .warmth) ?? .default
        enthusiasm = try container.decodeIfPresent(Level.self, forKey: .enthusiasm) ?? .default
        emoji = try container.decodeIfPresent(Level.self, forKey: .emoji) ?? .default
        customInstructions = try container.decodeIfPresent(String.self, forKey: .customInstructions) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        moreAboutYou = try container.decodeIfPresent(String.self, forKey: .moreAboutYou) ?? ""
    }

    /// nil when every knob is `.default` and every string is blank.
    func promptFragment() -> String? {
        var lines: [String] = []

        switch baseTone {
        case .default: break
        case .direct:
            lines.append("Be blunt and economical. Lead with the answer, skip the preamble.")
        case .encouraging:
            lines.append("Be encouraging. Name what the founder got right before what to fix.")
        case .analytical:
            lines.append("Be analytical. Show the reasoning and the trade-offs behind advice.")
        }

        switch warmth {
        case .default: break
        case .more: lines.append("Warmer than usual: acknowledge how the work is going.")
        case .less: lines.append("Cooler than usual: no pleasantries, no check-ins.")
        }

        switch enthusiasm {
        case .default: break
        case .more: lines.append("Show more enthusiasm when something is working.")
        case .less: lines.append("Stay level. No exclamation marks, no celebration.")
        }

        switch emoji {
        case .default: break
        // Overrides the "No emoji" clause in the base system prompt.
        case .more: lines.append("A single relevant emoji per reply is welcome.")
        case .less: lines.append("Never use emoji.")
        }

        let r = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { lines.append("The founder describes their role as: \(r).") }

        let more = moreAboutYou.trimmingCharacters(in: .whitespacesAndNewlines)
        if !more.isEmpty { lines.append("Keep in mind about the founder: \(more).") }

        // Last, so an explicit instruction wins over the knobs above it.
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { lines.append(custom) }

        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
