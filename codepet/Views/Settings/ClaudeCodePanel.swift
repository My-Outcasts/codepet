import SwiftUI
import AppKit

/// Connects Codepet to the founder's own Claude plan.
///
/// **Two separate things, deliberately drawn as two rows.** A Mac has one Claude Code
/// login, in the Keychain, and `claude` neither knows nor cares who spawned it — so the
/// moment Codepet can find that login it can also spend it. The first row is therefore a
/// FACT Codepet observed about the machine; the second is a DECISION the founder makes.
/// An earlier version of this panel drew only the first and labelled it "Connected",
/// which told a founder who had signed into Claude Code months earlier, in a terminal,
/// for unrelated reasons, that they had connected something. They had not.
///
/// Codepet never holds a credential: `claude auth login` opens the browser itself, runs a
/// local callback server, and leaves the result in the Keychain that Claude Code owns.
/// Codepet spawns the process and reads `claude auth status --json`. That is also why
/// `claude setup-token` is not used despite fitting a GUI more tidily — it prints a
/// one-year token and saves it nowhere, which would make Codepet the holder.
struct ClaudeCodePanel: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    @StateObject private var login = CLILogin()
    /// One probe per provider — the install-and-auth half of this panel is no longer
    /// Claude-only. Row one (machine facts) and the login flow below still read only
    /// `claudeStatus`, since `CLILogin` itself is Claude's own login flow; the grant
    /// rows in `grantGroup` are what read every entry.
    @State private var status: [AIProvider: CLIStatus] = [:]
    @State private var probing = true
    @State private var pastedCode = ""
    @State private var copied = false
    /// The switch is `@State`, not read straight from storage on every render.
    ///
    /// Reading storage inside `Toggle`'s `get:` looks simpler and does not work: nothing is
    /// published, so SwiftUI has no reason to re-render after a write and the switch snaps
    /// back to its old position while the value it wrote is sitting in `UserDefaults`. The
    /// founder sees a switch that refuses to move, flips it again, and writes the opposite.
    /// It only appears to work today because `setAuthorised` is followed by `refresh()`,
    /// whose `@State` writes re-render the view by accident — an accident this removes
    /// rather than relies on.
    ///
    /// A `Set<AIProvider>`, not a `Bool`, now that a Mac can hold a grant for Claude, for
    /// Codex, for both, or for neither — the same reasoning, one bit per provider instead
    /// of one bit total. `ProviderAuthorisation.setAuthorised` is still called with a single
    /// `AIProvider` at a time, so revoking one never touches the other's membership here.
    @State private var granted: Set<AIProvider> = []

    /// The provider whose revoke is waiting on the founder's answer; nil when nothing is
    /// asked. Deferring the write (rather than writing and offering an undo) is what makes
    /// Cancel free: `granted` is never mutated, so the toggle simply stays where it was.
    @State private var pendingRevoke: AIProvider?

    /// Injected so a test or preview never touches the real defaults domain.
    var authorisation = ProviderAuthorisation()

    /// The documented native installer. Shown for copying, never run on the founder's
    /// behalf: they should see what is about to be put on their machine. Reads
    /// `AIProvider.installCommand` — the one shared copy, so this panel and
    /// `OnboardingProviderStep` can never drift onto two different install commands.
    private static let installCommand = AIProvider.claudeCode.installCommand

    private var companyId: String? { companyStore.companyId }

    /// Row one, the login flow, and the billing warning below are all about Claude's own
    /// login on this Mac — `CLILogin` only knows how to sign into Claude Code — so they
    /// keep reading this single entry rather than every provider's status.
    private var claudeStatus: CLIStatus { status[.claudeCode] ?? .unprobed(.claudeCode) }

    /// Which providers get a row at all: signed in now, OR already granted.
    ///
    /// The original rule was "installed AND signed in" alone — asking before that is a
    /// decision about nothing, so a founder with no Codex on her Mac saw no Codex row.
    /// True as far as it went, but it also meant a STORED grant vanished the moment its
    /// CLI went unreachable: sign out of Codex (no uninstall needed) and its row simply
    /// stops rendering, taking the only toggle that could revoke it with it. The grant
    /// sits on disk, unreviewable, and comes back ON — unattended, no fresh consent —
    /// the moment she signs back in. Settings exists to review and revoke a grant; a
    /// grant a founder cannot even see fails that on its own terms.
    ///
    /// `ProviderGrantRow.rowsToShow` is the fix: OR in `granted`, so a stored grant
    /// always gets a row even while its CLI is unreachable. `grantRow` renders that case
    /// with the toggle already on and an honest "not reachable right now" line, so
    /// switching it off is still obviously possible — probing never grants, and it must
    /// never silently revoke either.
    private var rowsToShow: [AIProvider] {
        ProviderGrantRow.rowsToShow(status: status, granted: granted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(label: lang == .vi ? "Claude Code trên máy này" : "Claude Code on this Mac",
                            description: machineDescription) {
                    machineControl
                }
            }

            // Only offered once there is a login to authorise. Asking before that is a
            // decision about nothing.
            if let companyId, !rowsToShow.isEmpty {
                grantGroup(companyId: companyId)
            }

            if case .needsCode = login.phase {
                codeGroup
            }

            if claudeStatus.blocker == .notInstalled && !probing {
                installGroup
            }

            if let url = login.loginURL, login.isRunning {
                urlGroup(url)
            }

            if let warning = claudeStatus.billingWarning {
                noteLine(warningText(warning), colour: CodepetTheme.accentOrange)
            }

            if case .failed(let reason) = login.phase {
                noteLine(reason, colour: CodepetTheme.accentOrange)
            }

            noteLine(lang == .vi
                     ? "Codepet không bao giờ thấy hay lưu token của bạn. Claude Code giữ nó trong Keychain của máy."
                     : "Codepet never sees or stores your token. Claude Code keeps it in your Mac's Keychain.",
                     colour: CodepetTheme.mutedText)
        }
        .task { await refresh() }
        .onChange(of: login.phase) { _, phase in
            if case .signedIn = phase { Task { await refresh() } }
        }
        // Claude off stops the product, so it is worth one question. Cancel writes nothing:
        // the toggle's `get:` reads `granted`, which the deferred path never touched.
        .alert(GrantCopy.revokeTitle(lang: lang),
               isPresented: Binding(get: { pendingRevoke != nil },
                                    set: { if !$0 { pendingRevoke = nil } })) {
            Button(GrantCopy.revokeCancel(lang: lang), role: .cancel) { pendingRevoke = nil }
            Button(GrantCopy.revokeConfirm(lang: lang), role: .destructive) {
                if let p = pendingRevoke, let cid = companyId {
                    applyGrant(provider: p, companyId: cid, on: false)
                }
                pendingRevoke = nil
            }
        } message: {
            Text(GrantCopy.revokeBody(lang: lang))
        }
    }

    // MARK: - Row one: what is true about this Mac

    private var machineDescription: String {
        if probing { return lang == .vi ? "Đang kiểm tra…" : "Checking…" }
        switch claudeStatus.blocker {
        case .notInstalled:
            return lang == .vi ? "Chưa tìm thấy Claude Code trên máy này."
                               : "Claude Code isn't installed on this Mac."
        case .notSignedIn:
            return lang == .vi ? "Đã cài, chưa đăng nhập." : "Installed, but not signed in."
        // The fix is updating Claude Code, not signing in — so this must not send them to
        // a sign-in screen they are already past.
        case .versionUnknown:
            return lang == .vi ? "Bản Claude Code này quá cũ để đọc trạng thái đăng nhập. Hãy cập nhật."
                               : "This Claude Code is too old to report its sign-in state. Update it."
        // Signed in, whether or not the grant is given — the account is a fact either way.
        case .notAuthorised, nil:
            return accountLine
        }
    }

    /// States who is signed in, and says nothing about Codepet. The plan name is the
    /// useful half: it decides which models are reachable.
    private var accountLine: String {
        guard let account = claudeStatus.account else { return "" }
        var parts: [String] = []
        if let email = account.email { parts.append(email) }
        if let plan = account.subscriptionType {
            parts.append(lang == .vi ? "gói \(plan)" : "\(plan) plan")
        }
        if let org = account.orgName { parts.append(org) }
        return parts.isEmpty
            ? (lang == .vi ? "Đã đăng nhập." : "Signed in.")
            : parts.joined(separator: " · ")
    }

    @ViewBuilder private var machineControl: some View {
        if probing {
            ProgressView().controlSize(.small)
        } else if login.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(lang == .vi ? "Đang chờ trình duyệt…" : "Waiting for your browser…")
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                quietButton(lang == .vi ? "Huỷ" : "Cancel") { login.cancel() }
            }
        } else if claudeStatus.account != nil {
            HStack(spacing: 10) {
                Text(lang == .vi ? "Đã đăng nhập" : "Signed in")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentTeal)
                quietButton(lang == .vi ? "Kiểm tra lại" : "Re-check") { Task { await refresh() } }
            }
        } else if claudeStatus.blocker == .notInstalled {
            // Nothing to sign into yet. A sign-in button here is an instruction the
            // founder cannot follow.
            quietButton(lang == .vi ? "Kiểm tra lại" : "Re-check") { Task { await refresh() } }
        } else {
            primaryButton(lang == .vi ? "Đăng nhập" : "Sign in") { login.start() }
        }
    }

    // MARK: - Row two: what the founder allows

    /// One row per provider from `rowsToShow` — signed in now, or already granted.
    /// Consent is never transitive: each row's `Toggle` writes only its own provider, so
    /// revoking Codex here can never touch Claude's stored grant, or the reverse.
    @ViewBuilder private func grantGroup(companyId: String) -> some View {
        SettingsGroupLabel(lang == .vi ? "Quyền" : "Permission")
        SettingsGroup {
            ForEach(rowsToShow, id: \.self) { provider in
                grantRow(provider: provider, companyId: companyId)
                if provider != rowsToShow.last {
                    SettingsDivider()
                }
            }
        }
    }

    @ViewBuilder private func grantRow(provider: AIProvider, companyId: String) -> some View {
        // Reachable right now, i.e. this row would also have qualified under the old
        // "signed in" rule. When it did not — a stored grant with a signed-out or
        // uninstalled CLI — the row is here only because of the grant, and the toggle
        // reads as already on. The founder must be told why in that case, so switching
        // it off reads as obviously possible rather than as a bug.
        let reachable = status[provider]?.account != nil
        SettingsRow(
            label: lang == .vi ? "Cho Codepet dùng gói \(provider.displayName)"
                                : "Let Codepet use your \(provider.displayName) plan",
            // Names the actual cost, because that is what the founder is agreeing to —
            // "uses your quota" is the honest version of "connected". And names WHAT it
            // reaches, because the switch silently pulled chat over the moment it
            // existed, and a permission whose scope is invisible is not informed
            // consent. Every feature moved onto this path gets added to this line.
            description: reachable
                ? GrantCopy.description(for: provider, lang: lang)
                : GrantCopy.description(for: provider, lang: lang) + "\n\n" + unreachableNote(for: provider)
        ) {
            Toggle("", isOn: Binding(
                get: { granted.contains(provider) },
                set: { on in
                    // Turning OFF the kill switch asks first. Turning ON never does:
                    // granting is the recoverable direction, and a prompt there would be
                    // friction on the one move we want the founder to make.
                    if !on, GrantCopy.needsRevokeConfirm(provider) {
                        pendingRevoke = provider
                        return
                    }
                    applyGrant(provider: provider, companyId: companyId, on: on)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    /// The one place a grant is written from this panel. Both the confirmed revoke and
    /// every unconfirmed flip land here, so they can never disagree about what "off" does.
    private func applyGrant(provider: AIProvider, companyId: String, on: Bool) {
        if on { granted.insert(provider) } else { granted.remove(provider) }
        authorisation.setAuthorised(provider, companyId, on)
        Task { await refresh() }
    }

    /// Shown only on a row that exists solely because of a stored grant — never a
    /// silent revoke, just an honest reason the toggle is on with nothing running. The
    /// founder decides whether to switch it off; this line never does it for her.
    private func unreachableNote(for provider: AIProvider) -> String {
        lang == .vi
            ? "\(provider.displayName) hiện không sẵn sàng trên máy này — có thể đã đăng xuất hoặc chưa cài. Quyền vẫn còn ở đây; bạn có thể tắt bất cứ lúc nào."
            : "\(provider.displayName) isn't reachable on this Mac right now — signed out, or not installed. The grant is still here, and you can turn it off any time."
    }

    // MARK: - Conditional groups

    @ViewBuilder private var installGroup: some View {
        SettingsGroupLabel(lang == .vi ? "Cài Claude Code" : "Install Claude Code")
        SettingsGroup {
            SettingsRow(
                label: lang == .vi ? "Chạy lệnh này trong Terminal" : "Run this in Terminal",
                description: lang == .vi
                    ? "Cần gói Claude Pro, Max, Team hay Enterprise. Gói miễn phí không dùng được Claude Code."
                    : "Needs a Claude Pro, Max, Team, or Enterprise plan. The free plan can't use Claude Code."
            ) {
                primaryButton(copied ? (lang == .vi ? "Đã chép" : "Copied")
                                     : (lang == .vi ? "Chép lệnh" : "Copy command")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                    copied = true
                }
            }
            SettingsDivider()
            Text(Self.installCommand)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(CodepetTheme.bodyText)
                .textSelection(.enabled)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var codeGroup: some View {
        SettingsGroupLabel(lang == .vi ? "Dán mã từ trình duyệt" : "Paste the code from your browser")
        SettingsGroup {
            SettingsRow(
                label: lang == .vi ? "Mã đăng nhập" : "Login code",
                // Explains WHY they are seeing this, so it does not read as a failure.
                description: lang == .vi
                    ? "Trình duyệt hiện mã thay vì tự quay lại. Dán vào đây."
                    : "Your browser showed a code instead of returning here. Paste it below."
            ) {
                HStack(spacing: 8) {
                    TextField("", text: $pastedCode)
                        .textFieldStyle(.roundedBorder)
                        .font(CodepetTheme.inter(12))
                        .frame(width: 180)
                        .onSubmit { submitCode() }
                    primaryButton(lang == .vi ? "Gửi" : "Send") { submitCode() }
                }
            }
        }
    }

    @ViewBuilder private func urlGroup(_ url: String) -> some View {
        SettingsGroup {
            SettingsRow(label: lang == .vi ? "Trình duyệt không mở?" : "Browser didn't open?",
                        description: url) {
                primaryButton(lang == .vi ? "Mở" : "Open") {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
            }
        }
    }

    // MARK: - Bits

    /// A warning, never a block: both cases run fine, and refusing to run would be
    /// Codepet overruling the founder about their own billing.
    private func warningText(_ warning: CLIStatus.BillingWarning) -> String {
        switch warning {
        case .consoleAccount:
            return lang == .vi
                ? "Đây là tài khoản Console, nên mỗi lần chạy tính tiền theo token thay vì thuộc gói thuê bao."
                : "This is a Console account, so runs bill per token instead of being covered by a subscription."
        case .apiKeyInEnvironment:
            return lang == .vi
                ? "Máy này có API key trong môi trường, và nó được ưu tiên hơn gói thuê bao của bạn."
                : "This Mac has an API key in its environment, and it outranks your subscription."
        }
    }

    @ViewBuilder private func noteLine(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(CodepetTheme.inter(11))
            .foregroundColor(colour)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func primaryButton(_ title: String,
                                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.accentPurple))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func quietButton(_ title: String,
                                          action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(CodepetTheme.inter(12, weight: .medium))
            .foregroundColor(CodepetTheme.mutedText)
    }

    private func submitCode() {
        login.submitCode(pastedCode)
        pastedCode = ""
    }

    private func refresh() async {
        // Reload every provider's switch from storage, so the rendered position is
        // always what was actually persisted — including after an account switch. No
        // company id means no grant can exist yet, so every provider reads `false`
        // rather than guessing — the panel then shows the machine facts and offers no
        // toggle for any provider.
        granted = companyId.map { id in
            Set(AIProvider.allCases.filter { authorisation.isAuthorised($0, id) })
        } ?? []
        probing = true
        // Probed independently per provider — an uninstalled Codex must never affect
        // what Claude reports, or the reverse.
        var next: [AIProvider: CLIStatus] = [:]
        for provider in AIProvider.allCases {
            next[provider] = await CLIEnvironment.probe(provider: provider,
                                                        authorised: granted.contains(provider))
        }
        status = next
        probing = false
        copied = false
    }
}
