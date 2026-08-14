import SwiftUI

/// §5.4: where should Codepet build?
///
/// Shown after the FIRST Developer send that comes back `no_repo_linked`, not
/// before it. Letting the send hit the backend first is deliberate: the server
/// is the authority on whether a repo is linked, and `engStartRun` returns
/// that 409 at line 168 — before it reads the balance and long before it
/// creates a session — so the attempt costs nothing. A client that guessed
/// instead would either prompt someone who is already connected or skip the
/// prompt for someone who is not.
///
/// **Never a dead-end** (spec §7). Every state offers a way forward: no GitHub
/// gets the OAuth round-trip, no repos gets create, a failure gets the same
/// words the result bar uses. Closing the sheet leaves the refusal in the
/// transcript with a control that reopens this — the founder is never left
/// with an ask and no way to answer it.
struct ConnectRepoSheet: View {
    let repos: EngineeringRepoServing
    /// Called with the link once one exists, so the caller can retry the ask
    /// that opened this sheet. The sheet does not start runs.
    var onLinked: (EngRepoLink) -> Void
    var onCancel: () -> Void

    @Environment(\.uiLanguage) private var lang
    @State private var state: ConnectRepoState = .loading
    /// Which row is being linked, so only that row shows progress and the
    /// others do not all look like they were tapped.
    @State private var busyFullName: String?
    @State private var creating = false

    private var hue: Color { CodepetTheme.accentBlue }
    private var isBusy: Bool { busyFullName != nil || creating }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            footer
        }
        .padding(24)
        .frame(width: 460)
        .frame(maxHeight: 560)
        .background(CodepetTheme.pageBackground)
        .task { await load() }
    }

    // MARK: - the three states

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            row(Self.loadingText(lang: lang))

        case .needsGitHub:
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.needsGitHubText(lang: lang))
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(Self.connectGitHubLabel(lang: lang)) {
                    Task { await connectGitHub() }
                }
                .buttonStyle(CodepetPillButtonStyle())
                .disabled(isBusy)
            }

        case .choose(let list):
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.chooseText(lang: lang))
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(list) { repo in repoRow(repo) }
                    }
                }
                .frame(maxHeight: 260)
                createButton(secondary: true)
            }

        case .createOnly:
            VStack(alignment: .leading, spacing: 12) {
                // NOT an empty list. A picker with nothing in it reads as a
                // broken control; this says why there is nothing to pick.
                Text(Self.noReposText(lang: lang))
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                createButton(secondary: false)
            }

        case .failed(let error):
            VStack(alignment: .leading, spacing: 12) {
                // The same words the result bar uses — one refusal should not
                // have two phrasings depending on which screen it lands on.
                Text(EngineeringResultBar.message(for: error, lang: lang))
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if error.isRetryable {
                        Button(Self.retryLabel(lang: lang)) { Task { await load() } }
                            .buttonStyle(CodepetPillButtonStyle())
                    }
                    createButton(secondary: true)
                }
            }
        }
    }

    @ViewBuilder private func repoRow(_ repo: EngRepoChoice) -> some View {
        Button {
            Task { await link(repo) }
        } label: {
            HStack(spacing: 8) {
                Text(repo.owner + "/")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CodepetTheme.mutedText)
                Text(repo.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer(minLength: 8)
                if busyFullName == repo.fullName {
                    Text(Self.linkingText(lang: lang))
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(hue)
                } else if repo.isPrivate {
                    Text(Self.privateLabel(lang: lang))
                        .font(CodepetTheme.inter(10))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy && busyFullName != repo.fullName ? 0.4 : 1)
    }

    /// The button plus the line that says what it makes.
    ///
    /// The label alone reads as SAFE — "a new repo" cannot be misread as
    /// acting on the repos listed above it — but not as KNOWN: named what,
    /// public or private, in whose account? The hesitation to design against
    /// here is not "will this break something" but "what am I about to find in
    /// my namespace." The backend answers all three (`private: true`,
    /// `auto_init: true`, created through `/user/repos` so it lands in the
    /// founder's own account) and none of it was on screen. The sheet's
    /// subtitle answers the fear for the CONNECT path and says nothing about
    /// this one.
    ///
    /// No name is shown: `engCreateRepo` derives it with `repoSlug` from the
    /// company, and reproducing that slug here would be a second
    /// implementation free to drift from the one that actually names the repo.
    /// Better to promise less and be right.
    @ViewBuilder private func createButton(secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(creating ? Self.creatingText(lang: lang) : Self.createLabel(lang: lang)) {
                Task { await create() }
            }
            .buttonStyle(CodepetPillButtonStyle(
                fill: secondary ? CodepetTheme.mutedText.opacity(0.15) : CodepetTheme.accentPurple,
                foreground: secondary ? CodepetTheme.primaryText : .white
            ))
            .disabled(isBusy)

            Text(Self.createNote(lang: lang))
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - chrome

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.title(lang: lang))
                .font(CodepetTheme.inter(16, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(Self.subtitle(lang: lang))
                .font(CodepetTheme.inter(12))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            Spacer()
            Button(Self.notNowLabel(lang: lang), action: onCancel)
                .font(CodepetTheme.inter(12))
                .foregroundColor(CodepetTheme.mutedText)
                .buttonStyle(.plain)
                .disabled(isBusy)
        }
    }

    @ViewBuilder private func row(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.inter(13))
            .foregroundColor(CodepetTheme.mutedText)
    }

    // MARK: - actions

    private func load() async {
        state = .loading
        do {
            state = ConnectRepo.state(after: .success(try await repos.listRepos()))
        } catch let error as EngineeringError {
            state = ConnectRepo.state(after: .failure(error))
        } catch {
            state = ConnectRepo.state(after: .failure(.unknown(0)))
        }
    }

    private func connectGitHub() async {
        // Reuses the one working consent round-trip in this codebase. A second
        // implementation would be a second place for the callback-parsing bugs
        // to live.
        let result = await ConnectorAuth.shared.connect(.github)
        guard result == .connected else { return }
        await load()
    }

    private func link(_ repo: EngRepoChoice) async {
        busyFullName = repo.fullName
        defer { busyFullName = nil }
        do {
            onLinked(try await repos.link(fullName: repo.fullName))
        } catch let error as EngineeringError {
            // Back to a state with a way out. `repoUnusable` in particular
            // must not close the sheet: the fix is picking a different row,
            // which is on the screen the founder is already looking at.
            state = .failed(error)
        } catch {
            state = .failed(.unknown(0))
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            // nil name: `engCreateRepo` derives one from the company brief,
            // which is a better name than anything this sheet could invent
            // without asking the founder a second question.
            onLinked(try await repos.create(name: nil))
        } catch let error as EngineeringError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown(0))
        }
    }

    // MARK: - copy

    static func title(lang: AppLanguage) -> String {
        lang == .vi ? "Codepet nên làm việc ở đâu?" : "Where should Codepet build?"
    }

    static func subtitle(lang: AppLanguage) -> String {
        lang == .vi
            ? "Mọi thay đổi đều nằm trên một nhánh riêng — nhánh chính của bạn không bị đụng tới."
            : "Every change lands on its own branch — your main branch is never touched."
    }

    static func loadingText(lang: AppLanguage) -> String {
        lang == .vi ? "Đang tìm repo của bạn…" : "Looking for your repos…"
    }

    static func needsGitHubText(lang: AppLanguage) -> String {
        lang == .vi
            ? "Cần kết nối GitHub trước. Codepet chỉ đọc và ghi vào repo bạn chọn."
            : "Connect GitHub first. Codepet only reads and writes the repo you pick."
    }

    static func connectGitHubLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Kết nối GitHub" : "Connect GitHub"
    }

    static func chooseText(lang: AppLanguage) -> String {
        lang == .vi ? "Chọn một repo — mới đẩy gần đây nhất ở trên cùng."
                    : "Pick a repo — most recently pushed first."
    }

    static func noReposText(lang: AppLanguage) -> String {
        lang == .vi
            ? "GitHub đã kết nối, nhưng chưa có repo nào để chọn. Codepet có thể tạo một cái riêng tư cho bạn."
            : "GitHub is connected, but there are no repos to pick from yet. Codepet can make you a private one."
    }

    /// "Create a repo for me", not "Create". The founder is being told what
    /// gets made and for whom — the one thing to be unambiguous about here is
    /// that this makes something NEW rather than touching what they have.
    static func createLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Tạo repo mới cho tôi" : "Create a new repo for me"
    }

    /// Three facts, all of them true of what `engCreateRepo` actually does:
    /// `private: true`, `auto_init: true`, and `/user/repos` — the founder's
    /// own account, not an org of ours. Deliberately no repo NAME, because
    /// the backend derives it and a client-side guess could disagree.
    static func createNote(lang: AppLanguage) -> String {
        lang == .vi
            ? "Tạo một repo riêng tư trong tài khoản GitHub của bạn, có sẵn một commit đầu tiên."
            : "Creates a private repo in your GitHub account, with one commit to start from."
    }

    static func creatingText(lang: AppLanguage) -> String {
        lang == .vi ? "Đang tạo…" : "Creating…"
    }

    static func linkingText(lang: AppLanguage) -> String {
        lang == .vi ? "Đang kết nối…" : "Connecting…"
    }

    static func privateLabel(lang: AppLanguage) -> String {
        lang == .vi ? "riêng tư" : "private"
    }

    static func retryLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Thử lại" : "Try again"
    }

    /// "Not now", not "Cancel". Cancel reads as abandoning the ask they just
    /// typed; the ask is still in the transcript, and the refusal there has a
    /// control that reopens this sheet.
    static func notNowLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Để sau" : "Not now"
    }
}

#if DEBUG
/// A repo service with no network, so the sheet's three states are previewable
/// and drivable with no GitHub account.
final class MockRepoService: EngineeringRepoServing {
    enum Listing { case some, none, notConnected, unavailable }

    private let listing: Listing
    let linkError: EngineeringError?
    private(set) var linked: [String] = []
    private(set) var created = 0

    init(listing: Listing = .some, linkError: EngineeringError? = nil) {
        self.listing = listing
        self.linkError = linkError
    }

    func listRepos() async throws -> [EngRepoChoice] {
        switch listing {
        case .notConnected: throw EngineeringError.gitHubNotConnected
        case .unavailable: throw EngineeringError.unavailable
        case .none: return []
        case .some:
            return [
                EngRepoChoice(fullName: "monatruong/codepet", url: "https://github.com/monatruong/codepet",
                              defaultBranch: "main", isPrivate: true, pushedAt: "2026-08-13T04:00:00Z"),
                EngRepoChoice(fullName: "monatruong/devpet-landing", url: "https://github.com/monatruong/devpet-landing",
                              defaultBranch: "main", isPrivate: false, pushedAt: "2026-08-11T09:00:00Z")
            ]
        }
    }

    func link(fullName: String) async throws -> EngRepoLink {
        if let linkError { throw linkError }
        linked.append(fullName)
        return EngRepoLink(url: "https://github.com/\(fullName)", defaultBranch: "main", vercelSetupUrl: nil)
    }

    func create(name: String?) async throws -> EngRepoLink {
        created += 1
        return EngRepoLink(url: "https://github.com/monatruong/monas", defaultBranch: "main",
                           vercelSetupUrl: "https://vercel.com/new/clone")
    }
}

#Preview("Connect — has repos") {
    ConnectRepoSheet(repos: MockRepoService(listing: .some), onLinked: { _ in }, onCancel: {})
        .environment(\.uiLanguage, .en)
}

#Preview("Connect — no repos") {
    ConnectRepoSheet(repos: MockRepoService(listing: .none), onLinked: { _ in }, onCancel: {})
        .environment(\.uiLanguage, .en)
}

#Preview("Connect — GitHub not connected") {
    ConnectRepoSheet(repos: MockRepoService(listing: .notConnected), onLinked: { _ in }, onCancel: {})
        .environment(\.uiLanguage, .en)
}
#endif
