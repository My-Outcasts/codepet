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

        // 2) opening round — each department's first take (blind to each other)
        for d in depts {
            await beat(typing: d, 0.9)
            messages.append(TeamMsg(kind: .dept(d), text: TeamRoster.line(for: d.key, lang: lang)))
            await pause(0.3)
        }

        // 3) discussion round — each department reacts to the one before it, so the
        //    team visibly hashes it out (cross-talk) instead of just stacking takes.
        let reactors = Array(depts.dropFirst().prefix(4))
        for (idx, d) in reactors.enumerated() {
            let other = depts[idx]   // the department right before this one
            await beat(typing: d, 1.0)
            messages.append(TeamMsg(kind: .dept(d), text: TeamRoster.react(for: d.key, other: other.name, lang: lang)))
            await pause(0.3)
        }

        // 4) byte moderates the discussion into one converged reply
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
        var keys = scored.prefix(6).map { $0.0 }
        // Always convene a broad-enough team: fill to at least 4 in a sensible order
        // (product first, then go-to-market, then the supporting functions).
        for k in ["eng", "design", "mkt", "sales", "ops", "fin", "support", "legal"] where !keys.contains(k) {
            if keys.count >= 4 { break }
            keys.append(k)
        }
        return keys.compactMap { DepartmentCatalog.find($0) }
    }

    static func byteIntro(_ ask: String, _ depts: [Department], lang: AppLanguage) -> String {
        let names = joinNames(depts.map { $0.name }, lang: lang)
        return lang == .vi
            ? "Được — “\(ask)”. Để làm cho tới, mình mời \(names) vào bàn với nhau nhé:"
            : "Got it — “\(ask)”. To do this right, I’ll get \(names) to talk it through:"
    }

    static func byteSynth(_ ask: String, _ depts: [Department], lang: AppLanguage) -> String {
        guard !depts.isEmpty else { return "" }
        let steps = depts.enumerated()
            .map { (i, d) in "\(i + 1). \(d.name) — \(angle(for: d.key, lang: lang))" }
            .joined(separator: "\n")
        return lang == .vi
            ? "Sau khi các bên trao đổi, đây là thứ tự mình đề xuất cho “\(ask)”:\n\(steps)\nBắt đầu từ bước 1 — mình chạy luôn nhé?"
            : "After they talked it through, here’s the order I’d suggest for “\(ask)”:\n\(steps)\nStart with step 1 — want me to take it?"
    }

    static func line(for key: String, lang: AppLanguage) -> String {
        (lang == .vi ? linesVI[key] : linesEN[key]) ?? (lang == .vi ? "Mình sẽ lo phần này." : "I’ll take this part.")
    }

    /// A department reacting to another department's point — the cross-talk that
    /// makes it a discussion, not a stack of independent takes. `{other}` is filled
    /// with the name of the department being reacted to.
    static func react(for key: String, other: String, lang: AppLanguage) -> String {
        let t = (lang == .vi ? reactVI[key] : reactEN[key])
            ?? (lang == .vi ? "Về ý {other}, mình thấy hợp lý — bổ sung một góc nữa thôi." : "On {other}’s point, that works — just one more angle.")
        return t.replacingOccurrences(of: "{other}", with: other)
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
        "eng":     "Về kỹ thuật, mình chia thành 3 lát dựng dần thay vì làm hết một lượt:\n• Lát 1 — bản khung chạy được để trong tuần đã có cái bấm thử.\n• Lát 2 — nối dữ liệu thật + gắn đo lường xem người dùng có ở lại không.\n• Lát 3 — polish & tối ưu sau khi thấy tín hiệu.\nMình soạn code-change plan rõ (mục tiêu, cách làm, chỗ đụng tới) để bạn duyệt rồi đưa coding agent ship.\nSản phẩm: kế hoạch code-change + skeleton chạy được.",
        "design":  "Mình lo phần nhìn & cảm giác — mục tiêu là người mới “à, hiểu rồi” trong 10 giây:\n• Một thông điệp chính rõ phía trên, không để user phải đoán.\n• Bỏ hết bước thừa trước khi họ chạm được giá trị thật.\n• Một lời kêu gọi hành động (CTA) duy nhất, nổi bật.\nMình dựng flow bằng màn hình thật (wireframe có chú thích) để bạn quyết cái nào giữ.\nSản phẩm: bộ wireframe first-run + spec copy từng màn.",
        "mkt":     "Có sản phẩm rồi vẫn cần đúng người nghe tới — mình lo phần câu chuyện:\n• Chốt một positioning một câu, bám đúng nỗi đau của tệp mục tiêu.\n• 3–5 mẫu nội dung (post/email) để mồi, theo giọng của bạn.\n• Một chuỗi kích hoạt cho ai đã quan tâm (waitlist/follow).\nMình giao bản nháp để bạn duyệt, không tự đăng.\nSản phẩm: positioning + lịch nội dung 2 tuần + mẫu email kích hoạt.",
        "sales":   "Giai đoạn đầu user tới từng người, không tự nhiên đổ về:\n• Lọc 20 người “ấm” nhất (đã phản hồi, email công ty, đến từ giới thiệu).\n• DM tay từng người: nhắc lý do họ quan tâm + mời như một đặc quyền.\n• Chưa nhắc giá — xin dùng thử đổi lấy feedback.\nMình lên danh sách + mẫu tin nhắn theo từng phân khúc.\nSản phẩm: checklist lọc 20 người + bộ mẫu DM cá nhân hóa.",
        "fin":     "Trước khi đổ tiền, mình lo phần con số:\n• Dựng 2–3 mức giá kèm giả định chi phí/margin để so.\n• Test sẵn lòng trả bằng hành vi thật (nút trả tiền), không chỉ khảo sát.\n• Canh runway: rẻ trước, đo, rồi mới đầu tư thêm.\nQuyết định cuối vẫn là của bạn — mình đưa dữ liệu để chốt.\nSản phẩm: model giá 3 kịch bản + một cách đo willingness-to-pay.",
        "ops":     "Mình lo “đường ống” để mọi thứ chạy mà không phải mình bạn ôm hết:\n• Quy trình rõ từ đầu vào tới đầu ra, ai làm bước nào.\n• Checklist + công cụ để lặp lại được, không phụ thuộc trí nhớ.\n• Nhịp thu thập dữ liệu để học nhanh mỗi tuần.\nBạn chỉ việc cắm tài khoản vào là chạy.\nSản phẩm: bảng quy trình + checklist vận hành.",
        "support": "Mỗi câu hỏi của user là tín hiệu để sửa — mình lo phần đó:\n• Help Center gọn trả lời trước ~80% câu hỏi hay gặp.\n• Luồng triage để phản hồi không rơi + gom thành việc cần làm.\n• Vòng lặp “phản hồi → ưu tiên → sửa” để sản phẩm tốt dần.\nSản phẩm: Help Center bản đầu + luồng triage feedback.",
        "legal":   "Mình phủ phần pháp lý tối thiểu để ship không thành rủi ro:\n• Privacy Policy + Terms hợp với thế local-first của bạn.\n• Rà các tuyên bố (claim) trước khi công bố kẻo phải gỡ.\n• Kiểm phần thu thập dữ liệu/cookie nếu có form.\nMình draft từ template, nhờ luật sư liếc qua trước khi launch.\nSản phẩm: nháp Privacy + Terms + checklist tuân thủ.",
    ]
    private static let linesEN: [String: String] = [
        "eng":     "On the build, I’d slice it into three stages instead of one big push:\n• Stage 1 — a working skeleton so there’s something clickable this week.\n• Stage 2 — wire real data + instrument whether users stick.\n• Stage 3 — polish & optimize once there’s signal.\nI’ll draft a clear code-change plan (goal, approach, what it touches) for you to approve, then hand to your coding agent.\nDeliverable: a code-change plan + a working skeleton.",
        "design":  "I own look and feel — the goal is a newcomer thinking “ah, I get it” within ten seconds:\n• One clear headline up top, nothing left to guess.\n• Strip every step before they touch real value.\n• A single, prominent call to action.\nI’ll propose it as real screens (annotated wireframes) so you make the taste calls.\nDeliverable: a first-run wireframe set + per-screen copy spec.",
        "mkt":     "Even a great product needs the right people to hear about it — I own the story:\n• Nail a one-line positioning tied to the target’s real pain.\n• 3–5 content drafts (posts/emails) in your voice to prime interest.\n• An activation sequence for anyone already warm (waitlist/follows).\nI hand you drafts to approve — I don’t post on my own.\nDeliverable: positioning + a 2-week content calendar + activation emails.",
        "sales":   "Early on, users come one at a time, not on their own:\n• Filter the 20 warmest (replied before, work email, came via referral).\n• DM each by hand: recall why they cared + invite them as an insider.\n• No pricing yet — trade a trial for feedback.\nI’ll build the list + per-segment message templates.\nDeliverable: a 20-person shortlist checklist + a personalized DM kit.",
        "fin":     "Before spending, I own the numbers:\n• Build 2–3 price points with cost/margin assumptions to compare.\n• Test willingness-to-pay by real behavior (a pay button), not just surveys.\n• Watch runway: cheap first, measure, then invest.\nThe final call stays yours — I bring the data.\nDeliverable: a 3-scenario price model + a willingness-to-pay test.",
        "ops":     "I own the plumbing so it runs without everything landing on you:\n• A clear process from input to output, who does which step.\n• A checklist + tooling that’s repeatable, not memory-dependent.\n• A weekly data-collection rhythm to learn fast.\nYou just plug in your accounts and it runs.\nDeliverable: a process board + an operations checklist.",
        "support": "Every user question is a signal about what to fix — that’s mine:\n• A lean Help Center answering ~80% of the common questions up front.\n• A triage flow so nothing drops + it rolls up into a to-fix list.\n• A “feedback → prioritize → fix” loop so the product improves steadily.\nDeliverable: a first Help Center + a feedback triage flow.",
        "legal":   "I cover the legal minimum so shipping doesn’t become a liability:\n• A Privacy Policy + Terms tuned to your local-first posture.\n• A pass on public claims before launch, so nothing has to be pulled.\n• A check on data/cookie collection if there’s a form.\nI draft from templates; have a lawyer glance before launch.\nDeliverable: draft Privacy + Terms + a compliance checklist.",
    ]
    // Reactions — each references {other} (the department it's responding to), in that
    // department's own voice/stance, so the round reads as a real back-and-forth.
    private static let reactVI: [String: String] = [
        "eng":     "Nghe {other} xong mình lo về scope — làm hết một lượt sẽ chậm. Mình cắt còn bản chạy được trước, phần còn lại làm sau.",
        "design":  "Bổ sung ý {other}: làm gì thì làm, buổi đầu user phải “à, hiểu rồi” trong 10 giây — không thì phần phía trên đổ sông.",
        "mkt":     "Đồng ý với {other} phần lõi, nhưng nếu không kể được thành một câu thì khó bán. Mình cần nó đơn giản đủ để nói trong 1 dòng.",
        "sales":   "Góc của {other} ổn, nhưng 20 người đầu mình vẫn phải đi mời tay — đừng trông vào việc tự nhiên có người tới.",
        "fin":     "Ý {other} hay, nhưng để mình soi con số đã — đừng đốt tiền trước khi có tín hiệu trả phí. Làm bản rẻ, đo, rồi mới đổ thêm.",
        "ops":     "Để cái {other} nói chạy được thật thì cần quy trình, không thì mình bạn ôm hết. Mình dựng checklist cho nó tự chạy.",
        "support": "Nghe {other} xong, nhớ chừa đường cho phản hồi — thứ user kêu ca chính là thứ cần sửa kế tiếp.",
        "legal":   "Một lưu ý cho ý {other}: soi phần pháp lý trước khi công bố, kẻo phải gỡ xuống giữa chừng.",
    ]
    private static let reactEN: [String: String] = [
        "eng":     "Hearing {other}, I worry about scope — doing it all at once is slow. I’d cut to a working version first and add the rest later.",
        "design":  "Building on {other}: whatever we do, the first run has to click in ten seconds — otherwise the rest is wasted.",
        "mkt":     "I’m with {other} on the core, but if we can’t say it in one line it won’t sell. I need it simple enough to pitch in a sentence.",
        "sales":   "{other}’s angle works, but the first 20 users I still invite by hand — let’s not count on people just showing up.",
        "fin":     "{other} makes a good point, but let me check the numbers first — no burning cash before we see willingness to pay. Cheap version, measure, then invest.",
        "ops":     "For what {other} said to actually run, we need process — otherwise it all lands on you. I’ll build a checklist so it runs itself.",
        "support": "After {other}, let’s leave a channel for feedback — what users complain about is exactly what to fix next.",
        "legal":   "One flag on {other}’s idea: check the legal side before we announce, or we may have to pull it.",
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
