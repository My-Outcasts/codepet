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

    @StateObject private var login = ClaudeCodeLogin()
    @State private var status: ClaudeCodeStatus = .unprobed
    @State private var probing = true
    @State private var pastedCode = ""
    @State private var copied = false

    /// Injected so a test or preview never touches the real defaults domain.
    var authorisation = ClaudeCodeAuthorisation()

    /// The documented native installer. Shown for copying, never run on the founder's
    /// behalf: they should see what is about to be put on their machine.
    private static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    private var companyId: String? { companyStore.companyId }

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
            if status.account != nil, let companyId {
                grantGroup(companyId: companyId)
            }

            if case .needsCode = login.phase {
                codeGroup
            }

            if status.blocker == .notInstalled && !probing {
                installGroup
            }

            if let url = login.loginURL, login.isRunning {
                urlGroup(url)
            }

            if let warning = status.billingWarning {
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
    }

    // MARK: - Row one: what is true about this Mac

    private var machineDescription: String {
        if probing { return lang == .vi ? "Đang kiểm tra…" : "Checking…" }
        switch status.blocker {
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
        guard let account = status.account else { return "" }
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
        } else if status.account != nil {
            HStack(spacing: 10) {
                Text(lang == .vi ? "Đã đăng nhập" : "Signed in")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentTeal)
                quietButton(lang == .vi ? "Kiểm tra lại" : "Re-check") { Task { await refresh() } }
            }
        } else if status.blocker == .notInstalled {
            // Nothing to sign into yet. A sign-in button here is an instruction the
            // founder cannot follow.
            quietButton(lang == .vi ? "Kiểm tra lại" : "Re-check") { Task { await refresh() } }
        } else {
            primaryButton(lang == .vi ? "Đăng nhập" : "Sign in") { login.start() }
        }
    }

    // MARK: - Row two: what the founder allows

    @ViewBuilder private func grantGroup(companyId: String) -> some View {
        SettingsGroupLabel(lang == .vi ? "Quyền" : "Permission")
        SettingsGroup {
            SettingsRow(
                label: lang == .vi ? "Cho Codepet dùng gói này" : "Let Codepet use this plan",
                // Names the actual cost, because that is what the founder is agreeing to —
                // "uses your quota" is the honest version of "connected". And names WHAT it
                // reaches, because the switch silently pulled chat over the moment it
                // existed, and a permission whose scope is invisible is not informed
                // consent. Every feature moved onto this path gets added to this line.
                description: lang == .vi
                    ? "Chat sẽ chạy trên gói Claude của bạn, và mỗi lượt tiêu hạn mức của bạn. Tắt là Codepet quay lại đường cũ — Claude Code trong terminal không bị ảnh hưởng."
                    : "Chat runs on your Claude plan, and each turn spends your quota. Turn it off and Codepet goes back to the old route — your terminal's Claude Code is unaffected."
            ) {
                Toggle("", isOn: Binding(
                    get: { authorisation.isAuthorised(companyId) },
                    set: { authorisation.setAuthorised(companyId, $0); Task { await refresh() } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
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
    private func warningText(_ warning: ClaudeCodeStatus.BillingWarning) -> String {
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
        probing = true
        // No company id means no grant can exist yet, so the probe is told `false` rather
        // than guessing — the panel then shows the machine facts and offers no toggle.
        let granted = companyId.map { authorisation.isAuthorised($0) } ?? false
        status = await ClaudeCodeEnvironment.probe(authorised: granted)
        probing = false
        copied = false
    }
}
