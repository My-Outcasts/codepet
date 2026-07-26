// codepet/Models/Deliverable.swift
import Foundation

struct ChecklistItem: Codable, Hashable { var t: String; var done: Bool }
struct DocSection: Codable, Hashable { var h: String; var p: String }
struct PlanChange: Codable, Hashable { var area: String; var edit: String }
struct DmMessage: Codable, Hashable { var name: String; var note: String; var msg: String }

// calendar
struct CalendarItem: Codable, Hashable { var day: String; var kind: String; var body: String }
struct CalendarWeek: Codable, Hashable { var label: String; var items: [CalendarItem] }
struct CalendarPayload: Codable, Hashable { var weeks: [CalendarWeek] }

// sheet
struct SheetInput: Codable, Hashable { var val: Double; var min: Double; var max: Double; var step: Double }
struct SheetPayload: Codable, Hashable {
    var price: SheetInput
    var waitlist: SheetInput
    var conversion: SheetInput
    var churn: SheetInput
    var summary: String?
}

// site
struct SiteContent: Codable, Hashable { var h: String; var p: String }
struct SitePayload: Codable, Hashable {
    var title: String
    var brand: String
    var kicker: String
    var headline: String
    var headlineHi: String
    var sub: String
    var ctaPrimary: String
    var ctaSecondary: String
    var howEyebrow: String
    var howTitle: String
    var steps: [SiteContent]
    var featEyebrow: String
    var featTitle: String
    var features: [SiteContent]
    var quote: String
    var quoteBy: String
    var finalTitle: String
    var finalSub: String
    var finalCta: String
    var accent: String
    var footNote: String
}

// screens
struct Screen: Codable, Hashable {
    var name: String
    var time: String
    var kick: String
    var title: String
    var sub: String
    var art: String
    var cta: String
    var note: String
}
struct ScreensPayload: Codable, Hashable { var screens: [Screen] }

/// Structured per-kind fields returned by the runTask CF (A1). All optional — one
/// kind's fields are populated at a time; nil for legacy/markdown-only deliverables.
///
/// The wire payload is FLAT and discriminated by the deliverable's `kind`: for a given
/// deliverable, the JSON `payload` object contains only that kind's keys at the top
/// level (no nested "calendar"/"site"/etc wrapper key). Some kinds share a JSON key with
/// a different shape (`plan.steps: [String]` vs `site.steps: [{h,p}]`), so the 4 newer
/// kinds are modeled as their OWN nested sub-payload structs (each with its own
/// `CodingKeys`/field types), and decoded from the SAME flat keyed container via a
/// custom `init(from:)` using `try?` — a shape mismatch (e.g. attempting to decode
/// `site.steps` as `[String]`) fails silently to `nil` instead of throwing, so decoding
/// one kind's payload never breaks because of another kind's colliding key name.
struct DeliverablePayload: Codable, Hashable {
    // checklist
    var items: [ChecklistItem]?
    // doc
    var call: String?
    var sections: [DocSection]?
    var next: [String]?
    // plan
    var goal: String?
    var steps: [String]?
    var changes: [PlanChange]?
    var verify: [String]?
    var risks: String?
    // dms
    var messages: [DmMessage]?
    // calendar / sheet / site / screens — each its own struct so e.g. SitePayload.steps
    // ([SiteContent]) never collides with the top-level plan `steps` ([String]) above.
    var calendar: CalendarPayload?
    var sheet: SheetPayload?
    var site: SitePayload?
    var screens: ScreensPayload?

    init(items: [ChecklistItem]? = nil, call: String? = nil, sections: [DocSection]? = nil,
         next: [String]? = nil, goal: String? = nil, steps: [String]? = nil,
         changes: [PlanChange]? = nil, verify: [String]? = nil, risks: String? = nil,
         messages: [DmMessage]? = nil, calendar: CalendarPayload? = nil,
         sheet: SheetPayload? = nil, site: SitePayload? = nil, screens: ScreensPayload? = nil) {
        self.items = items
        self.call = call
        self.sections = sections
        self.next = next
        self.goal = goal
        self.steps = steps
        self.changes = changes
        self.verify = verify
        self.risks = risks
        self.messages = messages
        self.calendar = calendar
        self.sheet = sheet
        self.site = site
        self.screens = screens
    }

    private enum CodingKeys: String, CodingKey {
        case items, call, sections, next, goal, steps, changes, verify, risks, messages
        case calendar, sheet, site, screens
    }

    /// Custom decode: each existing flat field is decoded with `try?` (fail-open, as
    /// before), then each new sub-payload is attempted against the SAME flat container
    /// via its own `init(from:)` — also `try?`, so a shape mismatch against another
    /// kind's payload just yields `nil` rather than throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([ChecklistItem].self, forKey: .items)) ?? nil
        call = (try? c.decodeIfPresent(String.self, forKey: .call)) ?? nil
        sections = (try? c.decodeIfPresent([DocSection].self, forKey: .sections)) ?? nil
        next = (try? c.decodeIfPresent([String].self, forKey: .next)) ?? nil
        goal = (try? c.decodeIfPresent(String.self, forKey: .goal)) ?? nil
        steps = (try? c.decodeIfPresent([String].self, forKey: .steps)) ?? nil
        changes = (try? c.decodeIfPresent([PlanChange].self, forKey: .changes)) ?? nil
        verify = (try? c.decodeIfPresent([String].self, forKey: .verify)) ?? nil
        risks = (try? c.decodeIfPresent(String.self, forKey: .risks)) ?? nil
        messages = (try? c.decodeIfPresent([DmMessage].self, forKey: .messages)) ?? nil

        calendar = try? CalendarPayload(from: decoder)
        sheet = try? SheetPayload(from: decoder)
        site = try? SitePayload(from: decoder)
        screens = try? ScreensPayload(from: decoder)
    }
}

/// A deliverable kind — mirrors the web StructuredKind, plus `.other` for unknown
/// values. Rendering is uniform (markdown); kind drives only the badge + icon.
enum DeliverableKind: String, Codable, CaseIterable {
    case doc, post, email, legal, screens, sheet, site, dms, calendar, checklist, plan, text, other

    /// Map an arbitrary string to a known kind, unknown → `.other`.
    init(raw: String) { self = DeliverableKind(rawValue: raw) ?? .other }

    /// Decode fail-open: an unrecognized kind string becomes `.other`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeliverableKind(rawValue: raw) ?? .other
    }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .doc:       return lang == .vi ? "Tài liệu" : "Doc"
        case .post:      return lang == .vi ? "Bài đăng" : "Post"
        case .email:     return "Email"
        case .legal:     return lang == .vi ? "Pháp lý" : "Legal"
        case .screens:   return lang == .vi ? "Màn hình" : "Screens"
        case .sheet:     return lang == .vi ? "Bảng tính" : "Sheet"
        case .site:      return lang == .vi ? "Trang web" : "Site"
        case .dms:       return lang == .vi ? "Tin nhắn" : "DMs"
        case .calendar:  return lang == .vi ? "Lịch" : "Calendar"
        case .checklist: return lang == .vi ? "Danh sách" : "Checklist"
        case .plan:      return lang == .vi ? "Kế hoạch" : "Plan"
        case .text:      return lang == .vi ? "Văn bản" : "Text"
        case .other:     return lang == .vi ? "Khác" : "Other"
        }
    }

    var icon: String {
        switch self {
        case .doc:       return "doc.text"
        case .post:      return "megaphone"
        case .email:     return "envelope"
        case .legal:     return "checkmark.seal"
        case .screens:   return "rectangle.on.rectangle"
        case .sheet:     return "tablecells"
        case .site:      return "globe"
        case .dms:       return "bubble.left.and.bubble.right"
        case .calendar:  return "calendar"
        case .checklist: return "checklist"
        case .plan:      return "map"
        case .text:      return "text.alignleft"
        case .other:     return "doc"
        }
    }
}

/// A delivered work product. `body` is markdown, rendered uniformly by MarkdownView.
struct Deliverable: Codable, Hashable, Identifiable {
    let id: String
    var kind: DeliverableKind
    var title: String
    var body: String
    var createdAt: String?    // ISO-8601 (JSON-safe; newest-first sort is lexicographic)
    var sourceTaskId: String?
    var payload: DeliverablePayload?

    init(id: String = UUID().uuidString, kind: DeliverableKind, title: String, body: String,
         createdAt: String? = nil, sourceTaskId: String? = nil, payload: DeliverablePayload? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.sourceTaskId = sourceTaskId
        self.payload = payload
    }
}
