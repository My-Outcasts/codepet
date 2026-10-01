// codepet/Models/Deliverable.swift
import Foundation

/// `owner`/`due` are optional (CP-002 C) — a checklist filed before them has neither, and the
/// synthesized decode reads an absent optional as nil.
struct ChecklistItem: Codable, Hashable { var t: String; var done: Bool; var owner: String? = nil; var due: String? = nil }
/// `source` (CP-002 C) is what a doc section rests on; optional, and never set on a legal clause.
struct DocSection: Codable, Hashable { var h: String; var p: String; var source: String? = nil }
struct PlanChange: Codable, Hashable { var area: String; var edit: String }
/// One outreach message TEMPLATE, addressed to an audience — "lapsed journaler",
/// "r/CasualConversation" — never to a person (CP-002 B). The prompt used to ask for a "persona
/// placeholder" `name`, so the Library showed messages to people who do not exist, looking
/// exactly like messages to real prospects; the founder might have sent one.
///
/// Decodes the legacy `name` into `audience`, so every set filed before the change still opens,
/// now labelled as templates too — nothing in an old `name` says whether it was invented, so
/// the honest reading is the conservative one. Encodes `audience` only, so a re-saved set
/// migrates itself.
struct DmMessage: Codable, Hashable {
    var audience: String
    var note: String
    var msg: String

    init(audience: String, note: String, msg: String) {
        self.audience = audience
        self.note = note
        self.msg = msg
    }

    private enum CodingKeys: String, CodingKey { case audience, name, note, msg }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let audience = try c.decodeIfPresent(String.self, forKey: .audience) ?? ""
        self.audience = audience.isEmpty ? try c.decode(String.self, forKey: .name) : audience
        note = try c.decode(String.self, forKey: .note)
        msg = try c.decode(String.self, forKey: .msg)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(audience, forKey: .audience)
        try c.encode(note, forKey: .note)
        try c.encode(msg, forKey: .msg)
    }
}

// calendar — a plan in phases (CP-002 E1)

/// One thing on the plan. `when` and `format` were `day` and `kind` before CP-002 E1, and still
/// decode from those keys, so a calendar filed then keeps every field it had (founder decision,
/// 30 Sep). `channel` and `owner` are the spec's additions, empty when the plan did not say.
struct CalendarItem: Codable, Hashable {
    var when: String
    var format: String
    var channel: String
    var owner: String
    var body: String

    init(when: String, format: String, channel: String = "", owner: String = "", body: String) {
        self.when = when; self.format = format; self.channel = channel; self.owner = owner; self.body = body
    }

    private enum CodingKeys: String, CodingKey { case when, format, channel, owner, body, day, kind }

    /// Soft on every field: a missing one degrades to "" rather than nuking the whole plan.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        when = try c.decodeIfPresent(String.self, forKey: .when) ?? c.decodeIfPresent(String.self, forKey: .day) ?? ""
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(when, forKey: .when)
        try c.encode(format, forKey: .format)
        if !channel.isEmpty { try c.encode(channel, forKey: .channel) }
        if !owner.isEmpty { try c.encode(owner, forKey: .owner) }
        try c.encode(body, forKey: .body)
    }
}

/// A stretch of the plan: "Week 1", "Five days out", "Ship day". `from`/`to` are relative labels
/// ("T-5", "Day 8") or empty — never dates, because the plan is relative and the app does not
/// invent a date (the rule the .ics export already follows).
struct CalendarPhase: Codable, Hashable {
    var label: String
    var from: String
    var to: String
    var items: [CalendarItem]

    init(label: String, from: String = "", to: String = "", items: [CalendarItem]) {
        self.label = label; self.from = from; self.to = to; self.items = items
    }

    private enum CodingKeys: String, CodingKey { case label, from, to, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        items = try c.decodeIfPresent([CalendarItem].self, forKey: .items) ?? []
    }

    /// "T-5 → T-3", "T-5", or "" — the span as the viewer prints it.
    var span: String {
        switch (from.isEmpty, to.isEmpty) {
        case (false, false): return from == to ? from : "\(from) → \(to)"
        case (false, true):  return from
        case (true, false):  return to
        default:             return ""
        }
    }
}

/// A plan in phases. It was exactly two weeks of 2-3 posts; the demo's launch runway already
/// abused the week labels as phases ("Blocking", "Ship day") and the server cut it at two.
/// A legacy `weeks[]` decodes as one phase per week with no span. Written as `phases` only, so a
/// re-saved calendar migrates itself. Throws when neither key is present, which keeps a
/// non-calendar payload (decoded from the same flat container) from growing one.
struct CalendarPayload: Codable, Hashable {
    var phases: [CalendarPhase]

    init(phases: [CalendarPhase]) { self.phases = phases }

    private enum CodingKeys: String, CodingKey { case phases, weeks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.phases) {
            phases = try c.decode([CalendarPhase].self, forKey: .phases)
        } else {
            phases = try c.decode([CalendarPhase].self, forKey: .weeks)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phases, forKey: .phases)
    }
}

// sheet
// `SheetPayload` and its parts live in `SheetModel.swift` since CP-002 D (any model, not four
// fixed inputs). `SheetInput` stays here: it is the shape of one of the OLD fixed four, which the
// sheet decoder still reads in order to lift them.
struct SheetInput: Codable, Hashable { var val: Double; var min: Double; var max: Double; var step: Double }

// site — a hero, typed blocks in any order, a closing CTA (CP-002 E2)
struct SiteContent: Codable, Hashable { var h: String; var p: String }

struct SiteTier: Codable, Hashable {
    var name: String
    var price: String
    var period: String
    var points: [String]
    var cta: String
    var highlight: Bool

    init(name: String, price: String, period: String = "", points: [String] = [], cta: String = "", highlight: Bool = false) {
        self.name = name; self.price = price; self.period = period; self.points = points; self.cta = cta; self.highlight = highlight
    }

    private enum CodingKeys: String, CodingKey { case name, price, period, points, cta, highlight }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        price = try c.decodeIfPresent(String.self, forKey: .price) ?? ""
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
        points = try c.decodeIfPresent([String].self, forKey: .points) ?? []
        cta = try c.decodeIfPresent(String.self, forKey: .cta) ?? ""
        highlight = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
    }
}

/// One section between the hero and the closing CTA. `type` is kept as a string so a future type
/// decodes rather than failing the page; `SiteViewer` draws the six it knows and skips the rest.
/// Only the fields a type uses are filled: `items` for steps/features/faq, `text` (+ `by`) for
/// quote/text, `tiers` for pricing.
struct SiteBlock: Codable, Hashable {
    var type: String
    var eyebrow: String
    var title: String
    var items: [SiteContent]
    var text: String
    var by: String
    var tiers: [SiteTier]

    init(type: String, eyebrow: String = "", title: String = "", items: [SiteContent] = [],
         text: String = "", by: String = "", tiers: [SiteTier] = []) {
        self.type = type; self.eyebrow = eyebrow; self.title = title; self.items = items
        self.text = text; self.by = by; self.tiers = tiers
    }

    private enum CodingKeys: String, CodingKey { case type, eyebrow, title, items, text, by, tiers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        eyebrow = try c.decodeIfPresent(String.self, forKey: .eyebrow) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        items = (try? c.decodeIfPresent([SiteContent].self, forKey: .items)) ?? []
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        by = try c.decodeIfPresent(String.self, forKey: .by) ?? ""
        tiers = (try? c.decodeIfPresent([SiteTier].self, forKey: .tiers)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(eyebrow, forKey: .eyebrow)
        try c.encode(title, forKey: .title)
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        if !text.isEmpty { try c.encode(text, forKey: .text) }
        if !by.isEmpty { try c.encode(by, forKey: .by) }
        if !tiers.isEmpty { try c.encode(tiers, forKey: .tiers) }
    }
}

struct SitePayload: Codable, Hashable {
    var title: String
    var brand: String
    var kicker: String
    var headline: String
    var headlineHi: String
    var sub: String
    var ctaPrimary: String
    var ctaSecondary: String
    var blocks: [SiteBlock]
    var finalTitle: String
    var finalSub: String
    var finalCta: String
    var accent: String
    var footNote: String

    init(title: String, brand: String, kicker: String = "", headline: String, headlineHi: String = "",
         sub: String = "", ctaPrimary: String, ctaSecondary: String = "", blocks: [SiteBlock],
         finalTitle: String, finalSub: String = "", finalCta: String, accent: String = "", footNote: String = "") {
        self.title = title; self.brand = brand; self.kicker = kicker; self.headline = headline
        self.headlineHi = headlineHi; self.sub = sub; self.ctaPrimary = ctaPrimary; self.ctaSecondary = ctaSecondary
        self.blocks = blocks; self.finalTitle = finalTitle; self.finalSub = finalSub; self.finalCta = finalCta
        self.accent = accent; self.footNote = footNote
    }

    private enum CodingKeys: String, CodingKey {
        case title, brand, kicker, headline, headlineHi, sub, ctaPrimary, ctaSecondary
        case blocks, finalTitle, finalSub, finalCta, accent, footNote
        // the pre-CP-002-E2 flat sections, read only to lift them into `blocks`
        case howEyebrow, howTitle, steps, featEyebrow, featTitle, features, quote, quoteBy
    }

    /// `title`, `brand`, `headline`, `ctaPrimary`, `finalTitle`, `finalCta` are the REQUIRED
    /// anchor fields — used unconditionally by `SiteViewer.buildHTML`, so they stay a plain
    /// `decode` and still THROW when absent. That is what keeps a PLAN payload (which has
    /// `steps` but no `title`) from decoding as a site. Everything else is soft.
    ///
    /// A page filed before CP-002 E2 has flat steps/features/quote and no `blocks`; they are
    /// lifted into blocks in the order the page always drew them, so `buildHTML` produces the
    /// same bytes it did (`SiteLegacyParityTests`). Encoding writes `blocks` only.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        brand = try c.decode(String.self, forKey: .brand)
        headline = try c.decode(String.self, forKey: .headline)
        ctaPrimary = try c.decode(String.self, forKey: .ctaPrimary)
        finalTitle = try c.decode(String.self, forKey: .finalTitle)
        finalCta = try c.decode(String.self, forKey: .finalCta)

        kicker = try c.decodeIfPresent(String.self, forKey: .kicker) ?? ""
        headlineHi = try c.decodeIfPresent(String.self, forKey: .headlineHi) ?? ""
        sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        ctaSecondary = try c.decodeIfPresent(String.self, forKey: .ctaSecondary) ?? ""
        finalSub = try c.decodeIfPresent(String.self, forKey: .finalSub) ?? ""
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? ""
        footNote = try c.decodeIfPresent(String.self, forKey: .footNote) ?? ""

        if c.contains(.blocks) {
            blocks = (try? c.decode([SiteBlock].self, forKey: .blocks)) ?? []
        } else {
            let str = { (k: CodingKeys) in (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
            let cards = { (k: CodingKeys) in (try? c.decodeIfPresent([SiteContent].self, forKey: k)) ?? [] }
            blocks = [
                SiteBlock(type: "steps", eyebrow: str(.howEyebrow), title: str(.howTitle), items: cards(.steps)),
                SiteBlock(type: "features", eyebrow: str(.featEyebrow), title: str(.featTitle), items: cards(.features)),
                SiteBlock(type: "quote", text: str(.quote), by: str(.quoteBy)),
            ].filter { !$0.items.isEmpty || !$0.text.isEmpty }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title); try c.encode(brand, forKey: .brand)
        try c.encode(kicker, forKey: .kicker); try c.encode(headline, forKey: .headline)
        try c.encode(headlineHi, forKey: .headlineHi); try c.encode(sub, forKey: .sub)
        try c.encode(ctaPrimary, forKey: .ctaPrimary); try c.encode(ctaSecondary, forKey: .ctaSecondary)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(finalTitle, forKey: .finalTitle); try c.encode(finalSub, forKey: .finalSub)
        try c.encode(finalCta, forKey: .finalCta); try c.encode(accent, forKey: .accent)
        try c.encode(footNote, forKey: .footNote)
    }
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

    private enum CodingKeys: String, CodingKey { case name, time, kick, title, sub, art, cta, note }

    /// `name`, `time`, `title` stay required (plain `decode`) — the anchor fields for a
    /// screen. `art` became soft in CP-002 E3: it is a description of the illustration now, and a
    /// screen may need none. `kick`/`sub`/`cta`/`note` are soft content and degrade to ""
    /// rather than throwing, so a CF omitting e.g. `note` on one screen doesn't nuke the whole
    /// screens payload.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        time = try c.decode(String.self, forKey: .time)
        title = try c.decode(String.self, forKey: .title)
        art = try c.decodeIfPresent(String.self, forKey: .art) ?? ""

        kick = try c.decodeIfPresent(String.self, forKey: .kick) ?? ""
        sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        cta = try c.decodeIfPresent(String.self, forKey: .cta) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
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
    var rulesOut: [String]?
    // post (CP-002 C) — the limit is the server's for a known platform, see `POST_PLATFORMS`
    var platform: String?
    var limit: Int?
    // email (CP-002 C) — `to` describes the recipient; never an address, never invented
    var subject: String?
    var to: String?
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
         next: [String]? = nil, rulesOut: [String]? = nil, platform: String? = nil,
         limit: Int? = nil, subject: String? = nil, to: String? = nil, goal: String? = nil, steps: [String]? = nil,
         changes: [PlanChange]? = nil, verify: [String]? = nil, risks: String? = nil,
         messages: [DmMessage]? = nil, calendar: CalendarPayload? = nil,
         sheet: SheetPayload? = nil, site: SitePayload? = nil, screens: ScreensPayload? = nil) {
        self.items = items
        self.call = call
        self.sections = sections
        self.next = next
        self.rulesOut = rulesOut
        self.platform = platform
        self.limit = limit
        self.subject = subject
        self.to = to
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
        case rulesOut = "rules_out", platform, limit, subject, to
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
        rulesOut = (try? c.decodeIfPresent([String].self, forKey: .rulesOut)) ?? nil
        platform = (try? c.decodeIfPresent(String.self, forKey: .platform)) ?? nil
        limit = (try? c.decodeIfPresent(Int.self, forKey: .limit)) ?? nil
        subject = (try? c.decodeIfPresent(String.self, forKey: .subject)) ?? nil
        to = (try? c.decodeIfPresent(String.self, forKey: .to)) ?? nil
        goal = (try? c.decodeIfPresent(String.self, forKey: .goal)) ?? nil
        steps = (try? c.decodeIfPresent([String].self, forKey: .steps)) ?? nil
        changes = (try? c.decodeIfPresent([PlanChange].self, forKey: .changes)) ?? nil
        verify = (try? c.decodeIfPresent([String].self, forKey: .verify)) ?? nil
        risks = (try? c.decodeIfPresent(String.self, forKey: .risks)) ?? nil
        messages = (try? c.decodeIfPresent([DmMessage].self, forKey: .messages)) ?? nil

        // Two forms reach this decoder. The server sends these four kinds FLAT (`{"price": …}`),
        // but the synthesized encoder writes each one NESTED under its own key
        // (`{"sheet": {"price": …}}`) — and that is the form `CompanyData.saveLibrary` stores.
        // Reading only the flat form dropped every one of these payloads on the next load, so a
        // filed site fell back to its markdown copy (`PayloadReloadTests`). Nested first, because
        // it is unambiguous; flat second, because a colliding key from another kind can pass it.
        calendar = (try? c.decodeIfPresent(CalendarPayload.self, forKey: .calendar)) ?? nil
            ?? (try? CalendarPayload(from: decoder))
        sheet = (try? c.decodeIfPresent(SheetPayload.self, forKey: .sheet)) ?? nil
            ?? (try? SheetPayload(from: decoder))
        site = (try? c.decodeIfPresent(SitePayload.self, forKey: .site)) ?? nil
            ?? (try? SitePayload(from: decoder))
        screens = (try? c.decodeIfPresent(ScreensPayload.self, forKey: .screens)) ?? nil
            ?? (try? ScreensPayload(from: decoder))
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

/// An earlier version of a Library item, kept when a revision replaces it in place.
///
/// Carries `kind` and `payload` as well as the text: a Site, sheet or calendar is DRAWN from its
/// payload, so a version that kept only the body would restore the words and keep showing the
/// newer layout.
struct DeliverableVersion: Codable, Hashable {
    var title: String
    var body: String
    var createdAt: String?
    var kind: DeliverableKind? = nil
    var payload: DeliverablePayload? = nil
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
    /// Which founder plan paid for this deliverable.
    ///
    /// Optional, and permanently so: every deliverable written before 16 Sep 2026 has no
    /// provenance, and there is no honest way to backfill one. The card renders this only
    /// when it is present — the Aug 10 rule, that a card which always carries a status
    /// line teaches you to stop reading it.
    ///
    /// Stored as the provider, not the model id. "Which plan paid for this" is the
    /// question a founder asks; the model that answered is a different, noisier fact, and
    /// on Codex it is not reported at all.
    var producedBy: AIProvider? = nil
    /// The folder a Team Build assembled, for the one Library entry that stands for the whole
    /// project. Client-only: nothing maps it into a `RunTaskRequest`, and `LibraryView` offers
    /// Open in Finder for any deliverable that carries one. Nil for every other deliverable.
    var projectPath: String? = nil
    /// On a draft: the Library item this draft is a new version of. Approving it replaces that
    /// item in place instead of filing a second one (CP-025). Nil on every first-pass draft.
    var supersedes: String? = nil
    /// On a Library item: its earlier versions, newest first. Nil until the item is first revised.
    var versions: [DeliverableVersion]? = nil

    init(id: String = UUID().uuidString, kind: DeliverableKind, title: String, body: String,
         createdAt: String? = nil, sourceTaskId: String? = nil, payload: DeliverablePayload? = nil,
         producedBy: AIProvider? = nil, projectPath: String? = nil, supersedes: String? = nil,
         versions: [DeliverableVersion]? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.sourceTaskId = sourceTaskId
        self.payload = payload
        self.producedBy = producedBy
        self.projectPath = projectPath
        self.supersedes = supersedes
        self.versions = versions
    }

    // `Codable` was fully synthesised before this field — no `CodingKeys` existed, so every
    // JSON key was the property name verbatim. Lenient decoding of `producedBy` (an unknown
    // provider string degrades to nil rather than throwing) needs a custom `init(from:)`,
    // which needs this enum. The first seven cases are the seven pre-existing property names,
    // copied verbatim — get one wrong and every stored deliverable fails to decode.
    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, createdAt, sourceTaskId, payload, producedBy, projectPath
        case supersedes, versions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(DeliverableKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        sourceTaskId = try c.decodeIfPresent(String.self, forKey: .sourceTaskId)
        payload = try c.decodeIfPresent(DeliverablePayload.self, forKey: .payload)
        // Lenient on purpose: a plain `decodeIfPresent(AIProvider.self, …)` throws on an
        // unrecognised rawValue and takes the whole deliverable down with it. Decode the raw
        // String first, then map it through `AIProvider(rawValue:)` so an unknown provider
        // (a future id an older build doesn't know) degrades to nil instead.
        producedBy = (try? c.decodeIfPresent(String.self, forKey: .producedBy))
            .flatMap { $0 }
            .flatMap(AIProvider.init(rawValue:))
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        supersedes = try c.decodeIfPresent(String.self, forKey: .supersedes)
        versions = try c.decodeIfPresent([DeliverableVersion].self, forKey: .versions)
    }

    // Written explicitly to match the custom decoder above — a custom `init(from:)` suppresses
    // only the synthesised DECODER; without this the synthesised encoder disappears too and
    // the round-trip test fails.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(sourceTaskId, forKey: .sourceTaskId)
        try c.encodeIfPresent(payload, forKey: .payload)
        // `AIProvider` is not itself `Codable` (only `Equatable`) — encode its rawValue String,
        // matching the manual rawValue decode above.
        try c.encodeIfPresent(producedBy?.rawValue, forKey: .producedBy)
        try c.encodeIfPresent(projectPath, forKey: .projectPath)
        try c.encodeIfPresent(supersedes, forKey: .supersedes)
        try c.encodeIfPresent(versions, forKey: .versions)
    }
}
