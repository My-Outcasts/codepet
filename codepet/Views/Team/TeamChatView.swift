// codepet/Views/Team/TeamChatView.swift
import SwiftUI
import Combine

/// DEMO tab — a basic group-chat that shows the multi-agent flow: the founder asks
/// to build something, byte routes to the relevant departments, each specialist
/// "joins" and contributes, then byte synthesizes one reply. Fully client-side and
/// simulated (no network / no API) — canned, department-scoped copy chosen from the
/// user's ask by keyword. It exists to feel the orchestration UX, not to ship work.
struct TeamChatView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @StateObject private var model = TeamChatModel()
    @State private var input = ""

    private var companion: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "byte" }
    private var companionColor: Color { PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple }

    private var examples: [String] {
        lang == .vi
            ? ["Làm landing page cho app", "Ra mắt trên Product Hunt", "Chốt giá gói Pro", "Mở closed beta"]
            : ["Build a landing page", "Launch on Product Hunt", "Set the Pro price", "Open a closed beta"]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { emptyState }
                        ForEach(model.messages) { m in row(m).id(m.id) }
                    }
                    .padding(18)
                }
                .onChange(of: model.messages.count) { _ in
                    if let last = model.messages.last {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            inputBar
        }
        .background(CodepetTheme.pageBackground)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill").foregroundColor(companionColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(lang == .vi ? "Đội ngũ" : "Team")
                    .font(.pixelSystem(size: 15, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Hỏi \(companion) muốn build gì — các phòng ban sẽ cùng vào."
                                 : "Tell \(companion) what to build — the departments jump in.")
                    .font(CodepetTheme.inter(11.5)).foregroundColor(CodepetTheme.mutedText)
            }
            Spacer()
            if !model.messages.isEmpty {
                Button { model.reset(); input = "" } label: {
                    Text(lang == .vi ? "Mới" : "New")
                        .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(companionColor)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().stroke(CodepetTheme.hairline))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Empty state + example chips
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lang == .vi ? "Bạn muốn build gì?" : "What do you want to build?")
                    .font(.pixelSystem(size: 16, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Gõ một ý tưởng, \(companion) sẽ kéo đúng phòng ban vào giúp."
                                 : "Type an idea and \(companion) pulls in the right departments.")
                    .font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTheme.mutedText)
            }
            FlowChips(items: examples) { pick in send(pick) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: Rows
    @ViewBuilder private func row(_ m: TeamMsg) -> some View {
        switch m.kind {
        case .user:            userRow(m.text)
        case .byte:            byteRow(m.text)
        case .dept(let d):     deptRow(d, m.text)
        case .typing(let d):   typingRow(d)
        }
    }

    private func userRow(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(CodepetTheme.inter(13)).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(CodepetTheme.accentPurple))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func byteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            avatar(companion.prefix(1).uppercased(), companionColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(companion).font(.pixelSystem(size: 10, weight: .bold)).foregroundColor(companionColor)
                Text(text)
                    .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.primaryText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(CodepetTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.hairline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 40)
        }
    }

    private func deptRow(_ d: Department, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            avatar(d.ab, d.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name).font(.pixelSystem(size: 10, weight: .bold)).foregroundColor(d.accent)
                Text(text)
                    .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.bodyText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(d.accent.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(d.accent.opacity(0.22)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 40)
        }
    }

    private func typingRow(_ d: Department?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            avatar(d?.ab ?? companion.prefix(1).uppercased(), d?.accent ?? companionColor)
            TypingDots()
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 13).fill(CodepetTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.hairline))
            Spacer(minLength: 40)
        }
    }

    private func avatar(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.pixelSystem(size: 10, weight: .bold)).foregroundColor(color)
            .frame(width: 26, height: 26)
            .background(Circle().fill(color.opacity(0.15)))
            .overlay(Circle().stroke(color.opacity(0.3)))
    }

    // MARK: Input
    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(lang == .vi ? "Mình muốn build…" : "I want to build…", text: $input)
                .textFieldStyle(.plain)
                .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.primaryText)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11).fill(CodepetTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(CodepetTheme.hairline))
                .onSubmit { send(input) }
                .disabled(model.isRunning)
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
                    .foregroundColor(canSend ? companionColor : CodepetTheme.mutedText)
            }
            .buttonStyle(.plain).disabled(!canSend)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var canSend: Bool {
        !model.isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ raw: String) {
        let ask = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty, !model.isRunning else { return }
        input = ""
        model.send(ask, companion: companion, lang: lang)
    }
}

// MARK: - Simulation model

struct TeamMsg: Identifiable {
    let id = UUID()
    enum Kind {
        case user
        case byte
        case dept(Department)
        case typing(Department?)   // nil = byte typing
    }
    let kind: Kind
    var text: String = ""
}

/// Drives the simulated multi-agent turn on a timeline (all client-side, no network).
/// Guards on `isRunning` so a second send can't interleave two turns.
@MainActor
final class TeamChatModel: ObservableObject {
    @Published private(set) var messages: [TeamMsg] = []
    @Published private(set) var isRunning = false

    private var companion = "byte"
    private var lang: AppLanguage = .en

    func reset() {
        guard !isRunning else { return }
        messages = []
    }

    func send(_ ask: String, companion: String, lang: AppLanguage) {
        guard !isRunning else { return }
        self.companion = companion
        self.lang = lang
        messages.append(TeamMsg(kind: .user, text: ask))
        Task { await run(ask) }
    }

    private func run(_ ask: String) async {
        isRunning = true
        defer { isRunning = false }
        let depts = TeamRoster.pick(for: ask)

        // 1) byte reads the ask + announces who it's pulling in
        await beat(typing: nil, 0.7)
        messages.append(TeamMsg(kind: .byte, text: TeamRoster.byteIntro(ask, depts, lang: lang)))
        await pause(0.35)

        // 2) each department "joins" and contributes
        for d in depts {
            await beat(typing: d, 0.9)
            messages.append(TeamMsg(kind: .dept(d), text: TeamRoster.line(for: d.key, lang: lang)))
            await pause(0.3)
        }

        // 3) byte weaves it into one reply
        await beat(typing: nil, 0.9)
        messages.append(TeamMsg(kind: .byte, text: TeamRoster.byteSynth(ask, depts, lang: lang)))
    }

    /// Show a typing bubble for `s` seconds, then remove it (next real message follows).
    private func beat(typing d: Department?, _ s: Double) async {
        let t = TeamMsg(kind: .typing(d))
        messages.append(t)
        await pause(s)
        messages.removeAll { $0.id == t.id }
    }

    private func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}

// MARK: - Routing + canned copy (the "simulation")

enum TeamRoster {
    /// Keyword → department scoring. Picks the 2–4 most relevant of the 8 real
    /// departments; falls back to a sensible build trio when nothing matches.
    static func pick(for ask: String) -> [Department] {
        let q = ask.lowercased()
        var scored: [(String, Int)] = []
        for (key, words) in keywords {
            let score = words.reduce(0) { $0 + (q.contains($1) ? 1 : 0) }
            if score > 0 { scored.append((key, score)) }
        }
        scored.sort { $0.1 > $1.1 }
        var keys = scored.prefix(4).map { $0.0 }
        if keys.count < 2 {
            for k in ["eng", "design", "mkt"] where !keys.contains(k) {
                keys.append(k); if keys.count >= 3 { break }
            }
        }
        return keys.compactMap { DepartmentCatalog.find($0) }
    }

    static func byteIntro(_ ask: String, _ depts: [Department], lang: AppLanguage) -> String {
        let names = joinNames(depts.map { $0.name }, lang: lang)
        return lang == .vi
            ? "Được — “\(ask)”. Để làm cho tới, mình kéo \(names) vào cùng nhé:"
            : "Got it — “\(ask)”. To do this right, I’ll pull in \(names):"
    }

    static func byteSynth(_ ask: String, _ depts: [Department], lang: AppLanguage) -> String {
        let parts = depts.map { "\($0.name) \(angle(for: $0.key, lang: lang))" }
        let list = parts.joined(separator: ", ")
        guard let first = depts.first else { return "" }
        return lang == .vi
            ? "Tóm lại cho “\(ask)”: \(list). Mình đề xuất bắt đầu từ \(first.name), rồi cuốn dần. Làm bước đầu luôn nhé?"
            : "So for “\(ask)”: \(list). I’d start with \(first.name) and build from there. Want me to take the first step?"
    }

    static func line(for key: String, lang: AppLanguage) -> String {
        (lang == .vi ? linesVI[key] : linesEN[key]) ?? (lang == .vi ? "Mình sẽ lo phần này." : "I’ll take this part.")
    }

    private static func angle(for key: String, lang: AppLanguage) -> String {
        (lang == .vi ? anglesVI[key] : anglesEN[key]) ?? ""
    }

    private static func joinNames(_ names: [String], lang: AppLanguage) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        let head = names.dropLast().joined(separator: ", ")
        return "\(head) \(lang == .vi ? "và" : "and") \(names.last!)"
    }

    // Keyword table (VI + EN), lowercased substring match.
    private static let keywords: [String: [String]] = [
        "eng":     ["app", "tính năng", "feature", "build", "xây", "làm", "code", "backend", "api", "kỹ thuật", "technical", "mvp", "prototype", "sản phẩm", "product"],
        "design":  ["landing", "web", "trang", "site", "page", "ui", "ux", "thiết kế", "design", "giao diện", "onboard", "first-run", "màn hình", "screen", "logo", "brand"],
        "mkt":     ["ra mắt", "launch", "product hunt", "marketing", "nội dung", "content", "post", "bài", "quảng cáo", "ads", "email", "social", "waitlist", "positioning", "story", "announce"],
        "sales":   ["user", "khách", "customer", "bán", "sale", "tester", "mời", "invite", "dm", "outreach", "đầu tiên", "first user"],
        "fin":     ["giá", "price", "pricing", "pro", "tiền", "money", "revenue", "doanh thu", "subscription", "gói", "cost", "chi phí", "runway", "budget"],
        "ops":     ["beta", "quy trình", "process", "ops", "vận hành", "checklist", "pipeline", "tự động", "automation", "machinery"],
        "support": ["support", "hỗ trợ", "help", "docs", "faq", "triage", "phản hồi", "feedback", "bug"],
        "legal":   ["legal", "pháp lý", "privacy", "terms", "gdpr", "compliance", "chính sách", "policy", "license", "giấy phép"],
    ]

    private static let linesVI: [String: String] = [
        "eng":     "Về kỹ thuật, mình chia nhỏ dựng dần: bản khung chạy được trước, polish sau. Mình sẽ soạn code-change plan rõ ràng để bạn duyệt rồi đưa coding agent ship.",
        "design":  "Mình lo phần nhìn & cảm giác: first-run cần đủ rõ để người mới hiểu trong 10 giây. Mình dựng flow bằng màn hình thật để bạn quyết cái nào giữ.",
        "mkt":     "Có sản phẩm rồi vẫn cần người nghe tới. Mình viết positioning + vài mẫu nội dung bám đúng giọng của bạn, giao bản nháp để duyệt.",
        "sales":   "Giai đoạn đầu bạn kiếm user từng người, không broadcast. Mình lên danh sách + mẫu tin nhắn ấm để mời đúng người.",
        "fin":     "Trước khi đẩy mạnh, mình dựng model giá/chi phí và một cách test nhanh mức sẵn lòng trả — quyết định vẫn của bạn.",
        "ops":     "Mình dựng phần “đường ống” để mọi thứ chạy trơn: quy trình + checklist, bạn chỉ việc cắm tài khoản vào.",
        "support": "Mỗi câu hỏi của user là tín hiệu để sửa. Mình dựng Help Center gọn + luồng triage để bạn học từ phản hồi.",
        "legal":   "Mình phủ phần pháp lý tối thiểu — draft từ template hợp với thế của bạn, nhờ luật sư liếc qua trước khi ship.",
    ]
    private static let linesEN: [String: String] = [
        "eng":     "On the build side, I’d ship this in stages — a working skeleton first, polish after. I’ll draft a clear code-change plan for you to approve, then hand to your coding agent.",
        "design":  "I’ve got the look and feel — the first run needs to land in ten seconds. I’ll propose it as real screens so you make the taste calls.",
        "mkt":     "Even a great product needs someone to hear about it. I’ll write the positioning plus a few content drafts in your voice for you to approve.",
        "sales":   "Early on you land users one by one, not by broadcasting. I’ll build the list plus warm DM templates to invite the right people.",
        "fin":     "Before you scale, I’ll build the price/cost model and a quick willingness-to-pay test — the call stays yours.",
        "ops":     "I’ll stand up the plumbing so it runs smoothly — the process and checklist; you just plug in your accounts.",
        "support": "Every user question is a signal about what to fix. I’ll build a lean Help Center plus a triage flow so you learn fast.",
        "legal":   "I’ll cover the legal minimum — drafted from templates tuned to your posture; have a lawyer glance before launch.",
    ]
    private static let anglesVI: [String: String] = [
        "eng": "dựng bản chạy được", "design": "làm first-run rõ ràng", "mkt": "kể câu chuyện đúng người",
        "sales": "mời user đầu tiên", "fin": "chốt giá có cơ sở", "ops": "cho quy trình chạy trơn",
        "support": "học từ phản hồi", "legal": "phủ pháp lý tối thiểu",
    ]
    private static let anglesEN: [String: String] = [
        "eng": "builds the working version", "design": "makes the first run land", "mkt": "tells the story to the right people",
        "sales": "lands your first users", "fin": "sets a grounded price", "ops": "keeps the process running",
        "support": "learns from feedback", "legal": "covers the legal minimum",
    ]
}

// MARK: - Small pieces

/// Simple wrapping chip row for example prompts.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text(item).font(CodepetTheme.inter(12.5, weight: .medium))
                    }
                    .foregroundColor(CodepetTheme.accentPurple)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.08)))
                    .overlay(Capsule().stroke(CodepetTheme.accentPurple.opacity(0.25)))
                }.buttonStyle(.plain)
            }
        }
    }
}

/// Three pulsing dots — the "agent is typing" indicator.
private struct TypingDots: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(CodepetTheme.mutedText).frame(width: 6, height: 6)
            }
        }
        .opacity(on ? 1 : 0.35)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = true }
        }
    }
}
