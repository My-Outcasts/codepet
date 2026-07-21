// codepet/Models/Deliverable.swift
import Foundation

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

    init(id: String = UUID().uuidString, kind: DeliverableKind, title: String, body: String,
         createdAt: String? = nil, sourceTaskId: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.sourceTaskId = sourceTaskId
    }
}
