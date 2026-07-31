// codepet/Views/Library/LibraryView.swift
import SwiftUI

// MARK: - Library metadata (web parity)
//
// Mirrors LIB_TAG / LIB_BUCKET / LIB_BORDER / LIVE_TYPES / LIB_SKIN from the web
// `lib/data.ts`. Kept as ONE small table so the whole poster wall reads as one
// system. Note: the native `DeliverableKind` enum has no `build` kind, so the web
// "Builds" bucket / build tag simply never appear here (dead-but-harmless entries).
private enum Lib {
    /// Bucket display order — a chip shows only when that bucket has items.
    static let border = ["Sites", "Prototypes", "Models", "Builds",
                         "Posts", "Emails", "Plans", "Outreach", "Docs", "Checklists"]

    /// kind → filter bucket.
    static func bucket(_ k: DeliverableKind) -> String {
        switch k {
        case .site:                    return "Sites"
        case .screens:                 return "Prototypes"
        case .sheet:                   return "Models"
        case .plan:                    return "Plans"
        case .post:                    return "Posts"
        case .email:                   return "Emails"
        case .calendar:                return "Plans"
        case .dms:                     return "Outreach"
        case .legal, .doc:             return "Docs"
        case .checklist:               return "Checklists"
        default:                       return "Docs"
        }
    }

    /// LIVE_TYPES — these render a filled "Live" pip; everything else is a draft.
    /// (web = site, sheet, build; native has no build kind.)
    static func isLive(_ k: DeliverableKind) -> Bool { k == .site || k == .sheet }

    /// Per-type accent, mapped from the web LIB_SKIN inks to the nearest theme token.
    static func accent(_ k: DeliverableKind) -> Color {
        switch k {
        case .site, .screens:          return CodepetTheme.accentPurple
        case .sheet, .dms:             return CodepetTheme.accentTeal
        case .plan:                    return CodepetTheme.accentBlue
        case .post, .email, .calendar: return CodepetTheme.accentOrange
        case .legal:                   return CodepetTheme.accentPink
        case .checklist:               return CodepetTheme.accentGold
        default:                       return CodepetTheme.mutedText
        }
    }

    /// LIB_TAG — the terse row tag per kind (EN + VI to match the app's style).
    static func tag(_ k: DeliverableKind, _ lang: AppLanguage) -> String {
        let vi = lang == .vi
        switch k {
        case .site:      return vi ? "web trực tiếp" : "live site"
        case .screens:   return vi ? "nguyên mẫu" : "prototype"
        case .sheet:     return vi ? "mô hình trực tiếp" : "live model"
        case .post:      return vi ? "bài đăng" : "social post"
        case .email:     return "email"
        case .calendar:  return vi ? "kế hoạch nội dung" : "content plan"
        case .legal:     return vi ? "nháp pháp lý" : "legal draft"
        case .dms:       return vi ? "tin nhắn tiếp cận" : "outreach DMs"
        case .checklist: return vi ? "danh sách kiểm" : "checklist"
        case .plan:      return vi ? "kế hoạch đổi mã" : "code-change plan"
        case .doc:       return vi ? "bản nháp" : "draft"
        default:         return k.label(lang)
        }
    }
}

private func pad2(_ n: Int) -> String { String(format: "%02d", n) }

/// The Library = delivered work. Web-parity poster wall: item-count header, bucket
/// filter chips, grouped by department (catalog order, unknown/none last), each row a
/// per-type OutcomePreview + tag + title + 2-line desc + live/draft pip. Tapping a row
/// opens the (unchanged) markdown detail sheet. Empty → an honest empty state.
struct LibraryView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var selected: Deliverable?
    @State private var filter: String = "all"   // "all" or a bucket name

    private var items: [Deliverable] {
        companyStore.company.library.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    // bucket → count across the whole library
    private var counts: [String: Int] {
        var c: [String: Int] = [:]
        for d in items { c[Lib.bucket(d.kind), default: 0] += 1 }
        return c
    }
    private var buckets: [String] { Lib.border.filter { (counts[$0] ?? 0) > 0 } }

    // fall back to "all" if the active bucket has emptied (mirrors web's activeFilter guard)
    private var activeFilter: String {
        (filter != "all" && (counts[filter] ?? 0) == 0) ? "all" : filter
    }
    private var liveN: Int { items.filter { Lib.isLive($0.kind) }.count }

    private var shown: [Deliverable] {
        items.filter { activeFilter == "all" || Lib.bucket($0.kind) == activeFilter }
    }

    /// Resolve a deliverable's department key via its source task (web groups by `x.k`).
    private func deptKey(_ d: Deliverable) -> String? {
        guard let tid = d.sourceTaskId else { return nil }
        return companyStore.company.tasks.first { $0.id == tid }?.dept
    }

    /// Grouped by department in catalog order; unknown / unresolved → one "Other" group last.
    private var groups: [(dept: Department?, items: [Deliverable])] {
        var byKey: [String: [Deliverable]] = [:]
        for d in shown { byKey[deptKey(d) ?? "__other", default: []].append(d) }

        var out: [(Department?, [Deliverable])] = []
        let known = Set(DepartmentCatalog.all.map { $0.key })
        for dep in DepartmentCatalog.all {
            if let list = byKey[dep.key] { out.append((dep, list)) }
        }
        // everything without a catalog dept collapses into one trailing "Other" group
        var other: [Deliverable] = []
        for (k, list) in byKey where !known.contains(k) { other += list }
        if !other.isEmpty {
            other.sort { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            out.append((nil, other))
        }
        return out
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        filterBar
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                            groupSection(g.dept, g.items)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { DeliverableDetailView(deliverable: $0) }
    }

    // MARK: Header (title + subtitle + `NN items · NN live · NN draft`)

    private var header: some View {
        let n = items.count
        let draftN = n - liveN
        var idx = pad2(n) + " " + (lang == .vi ? "mục" : (n == 1 ? "item" : "items"))
        if liveN > 0 { idx += " · " + pad2(liveN) + " " + (lang == .vi ? "trực tiếp" : "live") }
        if draftN > 0 { idx += " · " + pad2(draftN) + " " + (lang == .vi ? "nháp" : "draft") }
        return VStack(alignment: .leading, spacing: 4) {
            Text(lang == .vi ? "Thư viện" : "Library")
                .font(.pixelSystem(size: 22, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi ? "Mọi thứ Codepet đã tạo hoặc phác thảo — bạn duyệt, gom về một nơi."
                             : "Everything Codepet has shipped or drafted — approved by you, kept in one place.")
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.mutedText)
            Text(idx)
                .font(.pixelSystem(size: 11, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }

    // MARK: Filter chips

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(lang == .vi ? "Tất cả" : "All", count: items.count, key: "all")
                ForEach(buckets, id: \.self) { b in
                    chip(b, count: counts[b] ?? 0, key: b)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ label: String, count: Int, key: String) -> some View {
        let on = activeFilter == key
        return Button { filter = key } label: {
            HStack(spacing: 5) {
                Text(label).font(.pixelSystem(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(.pixelSystem(size: 10, weight: .bold))
                    .foregroundColor(on ? Color.white.opacity(0.85) : CodepetTheme.mutedText)
            }
            .foregroundColor(on ? .white : CodepetTheme.bodyText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(on ? CodepetTheme.accentPurple : CodepetTheme.surface))
            .overlay(Capsule().stroke(on ? Color.clear : CodepetTheme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Department group

    private func groupSection(_ dept: Department?, _ list: [Deliverable]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(dept?.ab ?? "—")
                    .font(.pixelSystem(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(dept?.accent ?? CodepetTheme.mutedText))
                Text(dept?.name ?? (lang == .vi ? "Khác" : "Other"))
                    .font(.pixelSystem(size: 13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text("— \(list.count)")
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
                Spacer()
            }
            ForEach(list) { d in
                Button { selected = d } label: { LibraryRowView(deliverable: d) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30)).foregroundColor(CodepetTheme.mutedText)
            Text(lang == .vi ? "Sản phẩm sẽ xuất hiện ở đây" : "Delivered work will appear here")
                .font(.pixelSystem(size: 15, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi ? "Khi Codepet tạo ra sản phẩm, chúng sẽ tập hợp ở đây."
                             : "Once Codepet produces work, it collects here.")
                .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: 360)
    }
}

/// One library poster row — OutcomePreview thumbnail + tag + title + 2-line desc + live/draft pip.
struct LibraryRowView: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    /// First 2 non-empty lines of the markdown body.
    private var desc: String {
        deliverable.body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " ")
    }

    var body: some View {
        let k = deliverable.kind
        let live = Lib.isLive(k)
        return CodepetCard {
            HStack(alignment: .top, spacing: 12) {
                OutcomePreview(deliverable: deliverable)
                    .frame(width: 78, height: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Lib.tag(k, lang).uppercased())
                        .font(.pixelSystem(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(Lib.accent(k))
                    Text(deliverable.title)
                        .font(.pixelSystem(size: 13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(2)
                    if !desc.isEmpty {
                        Text(desc)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.bodyText)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(live ? CodepetTheme.accentTeal : Color.clear)
                            .overlay(Circle().stroke(live ? Color.clear : CodepetTheme.mutedText, lineWidth: 1))
                            .frame(width: 7, height: 7)
                        Text(live ? (lang == .vi ? "Trực tiếp" : "Live")
                                  : (lang == .vi ? "Bản nháp" : "Draft"))
                            .font(.pixelSystem(size: 10, weight: .medium))
                            .foregroundColor(live ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
                        Spacer()
                        Text(lang == .vi ? "mở →" : "open →")
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A small, purpose-built visual preview of a deliverable's outcome, shown on the left
/// of each poster row. Presentational only — static shapes tinted by the type's accent,
/// plus a few short real strings pulled from the structured payload (or the body's first
/// line when a kind has no native payload field). Ports the web OutcomePreview shapes.
struct OutcomePreview: View {
    let deliverable: Deliverable

    private var accent: Color { Lib.accent(deliverable.kind) }

    private var firstLine: String {
        deliverable.body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(accent.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1))
            .overlay(inner.padding(7))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private var inner: some View {
        switch deliverable.kind {
        case .site:      chrome
        case .screens:   phones
        case .plan:      steps
        case .sheet:     sheetRows
        case .post:      post
        case .email:     email
        case .calendar:  calendar
        case .dms:       dms
        case .checklist: checks
        default:         docPage   // doc, legal, text, other → generic doc look
        }
    }

    // browser chrome (site)
    private var chrome: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(accent.opacity(0.5)).frame(width: 4, height: 4)
                }
                Capsule().fill(accent.opacity(0.2)).frame(height: 4).frame(maxWidth: .infinity)
            }
            Capsule().fill(accent.opacity(0.45)).frame(width: 22, height: 5)
            Capsule().fill(accent.opacity(0.25)).frame(height: 3).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.25)).frame(width: 38, height: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // two phone rectangles (screens)
    private var phones: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.25)).frame(width: 20, height: 34)
            RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.45)).frame(width: 20, height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // numbered step bars (plan) — count follows payload.steps when present
    private var steps: some View {
        let n: Int = {
            if let s = deliverable.payload?.steps, !s.isEmpty { return min(s.count, 3) }
            return 3
        }()
        let widths: [CGFloat] = [40, 52, 30]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<n, id: \.self) { i in
                HStack(spacing: 5) {
                    Text("\(i + 1)")
                        .font(.pixelSystem(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(accent.opacity(0.7)))
                    Capsule().fill(accent.opacity(0.3)).frame(width: widths[i], height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // spreadsheet rows (sheet)
    private var sheetRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(accent.opacity(0.55)).frame(height: 5).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.25)).frame(height: 4).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.25)).frame(height: 4).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.25)).frame(width: 34, height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // avatar + name + body text (post)
    private var post: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(accent.opacity(0.5)).frame(width: 12, height: 12)
                Capsule().fill(accent.opacity(0.35)).frame(width: 26, height: 4)
            }
            Text(firstLine)
                .font(.pixelSystem(size: 8))
                .foregroundColor(CodepetTheme.bodyText)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // subject + 3 bars (email)
    private var email: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(firstLine.isEmpty ? "Email" : firstLine)
                .font(.pixelSystem(size: 8, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(1)
            Capsule().fill(accent.opacity(0.25)).frame(height: 3).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.25)).frame(height: 3).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.25)).frame(width: 30, height: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // 14-cell grid, cells 0/3/7/10 marked (calendar)
    private var calendar: some View {
        let marked: Set<Int> = [0, 3, 7, 10]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
            ForEach(0..<14, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(marked.contains(i) ? accent.opacity(0.6) : accent.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // generic doc page (doc / legal / default)
    private var docPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(accent.opacity(0.5)).frame(width: 24, height: 5)
            Capsule().fill(accent.opacity(0.22)).frame(height: 3).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.22)).frame(height: 3).frame(maxWidth: .infinity)
            Capsule().fill(accent.opacity(0.22)).frame(width: 40, height: 3)
            Capsule().fill(accent.opacity(0.22)).frame(height: 3).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // two chat bubbles, outgoing carries the first payload message (dms)
    private var dms: some View {
        let msg: String = {
            if let m = deliverable.payload?.messages?.first?.msg, !m.isEmpty { return m }
            return firstLine
        }()
        return VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(accent.opacity(0.22)).frame(width: 30, height: 10)
            HStack {
                Spacer(minLength: 0)
                Text(msg)
                    .font(.pixelSystem(size: 7))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.7)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // 4 check rows, done state from payload.items (checklist)
    private var checks: some View {
        let rows: [Bool] = {
            if let items = deliverable.payload?.items, !items.isEmpty {
                return items.prefix(4).map { $0.done }
            }
            return [true, true, false, false]
        }()
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, done in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(done ? accent.opacity(0.7) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(accent.opacity(0.5), lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .overlay(alignment: .center) {
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 5, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    Capsule().fill(accent.opacity(done ? 0.3 : 0.18)).frame(height: 3).frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Deliverable detail sheet — title + kind + the markdown body (scrolls).
struct DeliverableDetailView: View {
    let deliverable: Deliverable
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: deliverable.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                    .font(.system(size: 17))
                Text(deliverable.title)
                    .font(CodepetTheme.inter(18, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(16)
            Divider()
            ScrollView {
                DeliverableBodyView(deliverable: deliverable).padding(16)
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(CodepetTheme.pageBackground)
    }
}

/// The typed body rendering for a deliverable — the kind→viewer dispatch shared by
/// the Library's detail sheet and the Tasks draft-preview sheet, so both render every
/// deliverable kind identically without duplicating the switch.
struct DeliverableBodyView: View {
    let deliverable: Deliverable
    var body: some View {
        Group {
            switch deliverable.kind {
            case .checklist where !(deliverable.payload?.items?.isEmpty ?? true):
                ChecklistViewer(items: deliverable.payload!.items!)
            case .doc where !(deliverable.payload?.call?.isEmpty ?? true):
                DocViewer(call: deliverable.payload!.call!,
                          sections: deliverable.payload?.sections ?? [],
                          next: deliverable.payload?.next ?? [])
            case .plan where !(deliverable.payload?.goal?.isEmpty ?? true):
                PlanViewer(payload: deliverable.payload!)
            case .dms where !(deliverable.payload?.messages?.isEmpty ?? true):
                DmsViewer(messages: deliverable.payload!.messages!)
            case .calendar where deliverable.payload?.calendar != nil:
                CalendarViewer(payload: deliverable.payload!.calendar!)
            case .sheet where deliverable.payload?.sheet != nil:
                SheetViewer(payload: deliverable.payload!.sheet!)
            case .site where deliverable.payload?.site != nil:
                SiteViewer(payload: deliverable.payload!.site!)
            case .screens where deliverable.payload?.screens != nil:
                ScreensViewer(payload: deliverable.payload!.screens!)
            case .legal:
                LegalViewer(deliverable: deliverable)
            case .post:
                PostViewer(deliverable: deliverable)
            case .email:
                EmailViewer(deliverable: deliverable)
            default:
                MarkdownView(markdown: deliverable.body)
            }
        }
    }
}
