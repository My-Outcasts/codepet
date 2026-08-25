import SwiftUI
import AppKit

/// Connects Codepet to the founder's own Claude plan.
///
/// The one thing this panel must never imply is that Codepet holds a credential. It does
/// not: `claude auth login` opens the browser itself, runs a local callback server, and
/// stores the result in the macOS Keychain, which Claude Code owns. Codepet spawns the
/// process and then asks `claude auth status --json` who is signed in. That is the whole
/// mechanism, and it is why there is no key field anywhere on this screen.
///
/// No Terminal window either — an earlier design opened Terminal.app, which was worse for
/// no gain, since the CLI launches the browser on its own.
struct ClaudeCodePanel: View {
    @Environment(\.uiLanguage) private var lang

    @StateObject private var login = ClaudeCodeLogin()
    @State private var status: ClaudeCodeStatus = .unprobed
    @State private var probing = true
    @State private var pastedCode = ""
    @State private var copied = false

    /// The documented native installer. Shown for copying, never run for the founder:
    /// they should see what is about to be put on their machine.
    private static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(label: lang == .vi ? "Trạng thái" : "Status",
                            description: statusDescription) {
                    statusControl
                }
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
                warningLine(warning)
            }

            if case .failed(let reason) = login.phase {
                Text(reason)
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(lang == .vi
                 ? "Codepet không bao giờ thấy hay lưu token của bạn. Claude Code giữ nó trong Keychain của máy."
                 : "Codepet never sees or stores your token. Claude Code keeps it in your Mac's Keychain.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await refresh() }
        // A finished sign-in re-probes, so the row stops describing the old state.
        .onChange(of: login.phase) { _, phase in
            if case .signedIn = phase { Task { await refresh() } }
        }
    }

    // MARK: - Status row

    private var statusDescription: String {
        if probing { return lang == .vi ? "Đang kiểm tra…" : "Checking…" }
        switch status.blocker {
        case .notInstalled:
            return lang == .vi ? "Chưa tìm thấy Claude Code trên máy này."
                               : "Claude Code isn't installed on this Mac."
        case .notSignedIn:
            return lang == .vi ? "Đã cài, chưa đăng nhập."
                               : "Installed, but not signed in."
        // The fix is updating Claude Code, not signing in — so the copy must not send
        // them to a sign-in screen they are already past.
        case .versionUnknown:
            return lang == .vi ? "Bản Claude Code này quá cũ để đọc trạng thái đăng nhập. Hãy cập nhật."
                               : "This Claude Code is too old to report its sign-in state. Update it."
        case nil:
            return signedInDescription
        }
    }

    private var signedInDescription: String {
        guard let account = status.account else { return "" }
        var parts: [String] = []
        if let email = account.email { parts.append(email) }
        // The plan name is the useful half: it decides which models are reachable.
        if let plan = account.subscriptionType {
            parts.append(lang == .vi ? "gói \(plan)" : "\(plan) plan")
        }
        if let org = account.orgName { parts.append(org) }
        return parts.isEmpty
            ? (lang == .vi ? "Đã kết nối." : "Connected.")
            : parts.joined(separator: " · ")
    }

    @ViewBuilder private var statusControl: some View {
        if probing {
            ProgressView().controlSize(.small)
        } else if login.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(lang == .vi ? "Đang chờ trình duyệt…" : "Waiting for your browser…")
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                Button(lang == .vi ? "Huỷ" : "Cancel") { login.cancel() }
                    .buttonStyle(.plain)
                    .font(CodepetTheme.inter(12, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
        } else if status.isReady {
            HStack(spacing: 10) {
                Text(lang == .vi ? "Đã kết nối" : "Connected")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentTeal)
                Button(lang == .vi ? "Kiểm tra lại" : "Re-check") {
                    Task { await refresh() }
                }
                .buttonStyle(.plain)
                .font(CodepetTheme.inter(12, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
            }
        } else if status.blocker == .notInstalled {
            // Nothing to sign into yet. Offering a sign-in button here would be an
            // instruction the founder cannot follow.
            Button(lang == .vi ? "Kiểm tra lại" : "Re-check") {
                Task { await refresh() }
            }
            .buttonStyle(.plain)
            .font(CodepetTheme.inter(12, weight: .medium))
            .foregroundColor(CodepetTheme.mutedText)
        } else {
            primaryButton(lang == .vi ? "Kết nối" : "Connect") { login.start() }
        }
    }

    // MARK: - Groups

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
            SettingsRow(
                label: lang == .vi ? "Trình duyệt không mở?" : "Browser didn't open?",
                description: url
            ) {
                primaryButton(lang == .vi ? "Mở" : "Open") {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
            }
        }
    }

    @ViewBuilder private func warningLine(_ warning: ClaudeCodeStatus.BillingWarning) -> some View {
        // A warning, never a block: both cases run fine, and refusing to run would be
        // Codepet overruling the founder about their own billing.
        Text({
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
        }())
        .font(CodepetTheme.inter(11))
        .foregroundColor(CodepetTheme.accentOrange)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Bits

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

    private func submitCode() {
        login.submitCode(pastedCode)
        pastedCode = ""
    }

    private func refresh() async {
        probing = true
        status = await ClaudeCodeEnvironment.probe()
        probing = false
        copied = false
    }
}
