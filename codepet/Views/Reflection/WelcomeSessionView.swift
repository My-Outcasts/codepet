import SwiftUI

struct WelcomeSessionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var installer: HookInstaller
    @Environment(\.uiLanguage) private var uiLanguage

    @State private var showAdvanced: Bool = false

    private var pet: PetCharacter? { PetCharacter.all[appState.activeChar] }
    private var petName: String { pet?.name ?? "Pet" }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroBanner
            connectionCard
            if showAdvanced { advancedSection }
        }
        .onAppear {
            installer.checkInstallation()
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        HStack(alignment: .center, spacing: 16) {
            if let pet = pet {
                RoundedRectangle(cornerRadius: 16)
                    .fill(pet.color.opacity(0.14))
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(pet.color.opacity(0.35), lineWidth: 2)
                    )
                    .overlay(
                        Image(pet.imageName)
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: 50, height: 50)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(uiLanguage == .vi
                     ? "Chào, tôi là \(petName) \u{1F44B}"
                     : "Hi, I'm \(petName) \u{1F44B}")
                    .font(.pixelSystem(size: 17, weight: .bold))
                    .foregroundColor(ReflectionTheme.primaryText)
                Text(uiLanguage == .vi
                     ? "Kết nối Claude Code để bắt đầu ghi nhật ký reflection."
                     : "Connect Claude Code to start your reflection journal.")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(ReflectionTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: ReflectionTheme.accent.opacity(0.12),
                  borderColor: ReflectionTheme.accent,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    // MARK: - Connection Card (one-click)

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                statusIcon
                Text("Claude Code")
                    .font(.pixelSystem(size: 14, weight: .semibold))
                    .foregroundColor(ReflectionTheme.primaryText)
                Spacer()
                statusPill
            }

            switch installer.status {
            case .notInstalled:
                VStack(alignment: .leading, spacing: 12) {
                    Text(uiLanguage == .vi
                         ? "Bấm nút dưới đây để sao chép lệnh cài đặt, rồi dán vào Terminal."
                         : "Click below to copy the install command, then paste it in Terminal.")
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(ReflectionTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: { installer.install() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 13))
                            Text(uiLanguage == .vi ? "Sao chép lệnh cài đặt" : "Copy install command")
                        }
                    }
                    .buttonStyle(PixelButtonStyle(
                        fill: ReflectionTheme.accent,
                        foreground: .white,
                        paddingH: 20,
                        paddingV: 10,
                        blockSize: 2,
                        steps: 2,
                        borderWidth: 2,
                        shadowOffset: 3,
                        font: .pixelSystem(size: 13, weight: .semibold)
                    ))
                }

            case .installing:
                // "installing" = command was copied to clipboard
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(ReflectionTheme.moodCalm)
                            .font(.system(size: 14))
                        Text(uiLanguage == .vi ? "Đã sao chép!" : "Copied!")
                            .font(.pixelSystem(size: 13, weight: .medium))
                            .foregroundColor(ReflectionTheme.moodCalm)
                    }
                    Text(uiLanguage == .vi
                         ? "Mở Terminal → dán (⌘V) → nhấn Enter. Xong rồi bấm nút dưới đây."
                         : "Open Terminal → paste (⌘V) → press Enter. When done, click below.")
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(ReflectionTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button(action: { installer.verifyInstallation() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                Text(uiLanguage == .vi ? "Xong rồi" : "I've done it")
                            }
                        }
                        .buttonStyle(PixelButtonStyle(
                            fill: ReflectionTheme.moodCalm,
                            foreground: .white,
                            paddingH: 16,
                            paddingV: 8,
                            blockSize: 2,
                            steps: 2,
                            borderWidth: 2,
                            shadowOffset: 3,
                            font: .pixelSystem(size: 12, weight: .semibold)
                        ))

                        Button(action: { installer.install() }) {
                            Text(uiLanguage == .vi ? "Sao chép lại" : "Copy again")
                                .font(.pixelSystem(size: 12, weight: .medium))
                                .foregroundColor(ReflectionTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .installed:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(ReflectionTheme.accent)
                            .font(.system(size: 14))
                        Text(uiLanguage == .vi
                             ? "Đã cài xong! Khởi động lại Claude Code để bắt đầu."
                             : "All set! Restart Claude Code to start capturing.")
                            .font(.pixelSystem(size: 13))
                            .foregroundColor(ReflectionTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Re-install button (subtle)
                    Button(action: { installer.install() }) {
                        Text(uiLanguage == .vi ? "Cài lại" : "Reinstall")
                            .font(.pixelSystem(size: 11, weight: .medium))
                            .foregroundColor(ReflectionTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }

            case .failed(let error):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(ReflectionTheme.moodAlert)
                            .font(.system(size: 14))
                        Text(uiLanguage == .vi ? "Lỗi khi cài đặt" : "Installation failed")
                            .font(.pixelSystem(size: 13, weight: .medium))
                            .foregroundColor(ReflectionTheme.moodAlert)
                    }
                    Text(error)
                        .font(ReflectionTheme.mono(11))
                        .foregroundColor(ReflectionTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button(action: { installer.install() }) {
                            Text(uiLanguage == .vi ? "Thử lại" : "Try again")
                        }
                        .buttonStyle(PixelButtonStyle(
                            fill: ReflectionTheme.accent,
                            foreground: .white,
                            paddingH: 14,
                            paddingV: 8,
                            blockSize: 2,
                            steps: 2,
                            borderWidth: 2,
                            shadowOffset: 3,
                            font: .pixelSystem(size: 12, weight: .semibold)
                        ))

                        Button(action: { showAdvanced = true }) {
                            Text(uiLanguage == .vi ? "Cài thủ công" : "Install manually")
                                .font(.pixelSystem(size: 12, weight: .medium))
                                .foregroundColor(ReflectionTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Advanced toggle
            if installer.status != .failed("") {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(uiLanguage == .vi ? "Cài thủ công" : "Manual setup")
                            .font(.pixelSystem(size: 11, weight: .medium))
                    }
                    .foregroundColor(ReflectionTheme.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: cardFill, borderColor: cardBorder,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    // MARK: - Status helpers

    /// State-tinted wash so the card reads its status at a glance and feels
    /// lively instead of a flat white box. Connected = green, failed = red,
    /// working = blue, not-yet = the active character accent.
    private var cardFill: Color {
        switch installer.status {
        case .installed:    return ReflectionTheme.accent.opacity(0.14)
        case .failed:       return ReflectionTheme.reminderText.opacity(0.12)
        case .installing:   return ReflectionTheme.moodEngaged.opacity(0.12)
        case .notInstalled: return ReflectionTheme.accent.opacity(0.12)
        }
    }

    /// Full-color pixel frame (border + drop shadow) matching the status, so
    /// the card is framed in color instead of the neutral dark ink.
    private var cardBorder: Color {
        switch installer.status {
        case .installed:    return ReflectionTheme.accent
        case .failed:       return ReflectionTheme.reminderText
        case .installing:   return ReflectionTheme.moodEngaged
        case .notInstalled: return ReflectionTheme.accent
        }
    }

    /// Vivid badge — solid status disc + white glyph + soft outer ring + glow.
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.18))
                .frame(width: 46, height: 46)
            Circle()
                .fill(statusColor)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 1.5))
            Image(systemName: statusSystemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: statusColor.opacity(0.45), radius: 7, x: 0, y: 3)
    }

    /// Colored status capsule that sits at the trailing edge of the header.
    private var statusPill: some View {
        Text(statusLabel)
            .font(.pixelSystem(size: 11, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(statusColor.opacity(0.15)))
            .overlay(Capsule().stroke(statusColor.opacity(0.30), lineWidth: 1))
    }

    private var statusSystemImage: String {
        switch installer.status {
        case .notInstalled: return "link.badge.plus"
        case .installing:   return "arrow.triangle.2.circlepath"
        case .installed:    return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    private var statusLabel: String {
        switch installer.status {
        case .notInstalled:
            return uiLanguage == .vi ? "Chưa kết nối" : "Not connected"
        case .installing:
            return uiLanguage == .vi ? "Đang cài đặt..." : "Installing..."
        case .installed:
            return uiLanguage == .vi ? "Đã kết nối" : "Connected"
        case .failed:
            return uiLanguage == .vi ? "Lỗi" : "Error"
        }
    }

    private var statusColor: Color {
        switch installer.status {
        case .notInstalled: return ReflectionTheme.mutedText
        case .installing:   return ReflectionTheme.moodEngaged
        case .installed:    return ReflectionTheme.accent
        case .failed:       return ReflectionTheme.moodAlert
        }
    }

    // MARK: - Advanced (manual setup, collapsed by default)

    private static let settingsSnippet = """
    "hooks": {
      "UserPromptSubmit": [{
        "hooks": [{ "type": "command", "command": "~/.codepet/hooks/log-prompt.sh" }]
      }],
      "PostToolUse": [{
        "matcher": "*",
        "hooks": [{ "type": "command", "command": "~/.codepet/hooks/log-tool.sh" }]
      }],
      "Stop": [{
        "hooks": [{ "type": "command", "command": "~/.codepet/hooks/log-summary.sh" }]
      }],
      "SessionEnd": [{
        "hooks": [{ "type": "command", "command": "~/.codepet/hooks/log-session-end.sh" }]
      }]
    }
    """

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(uiLanguage == .vi ? "CÀI THỦ CÔNG" : "MANUAL SETUP")
                .font(.pixelSystem(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(ReflectionTheme.accent)

            manualStepCard(
                number: "1",
                title: uiLanguage == .vi ? "Cài hook scripts" : "Install hook scripts",
                description: uiLanguage == .vi
                    ? "Chạy trong Terminal (không cần ở trong thư mục project):"
                    : "Run in Terminal (works from any directory):",
                code: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Murror/CodePet-Clean/main/scripts/install-reflection-hooks.sh)\""
            )

            manualStepCard(
                number: "2",
                title: uiLanguage == .vi ? "Thêm hook config" : "Add hook config",
                description: uiLanguage == .vi
                    ? "Mở ~/.claude/settings.json và dán đoạn dưới vào key \"hooks\":"
                    : "Open ~/.claude/settings.json and merge under the \"hooks\" key:",
                code: Self.settingsSnippet
            )

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(ReflectionTheme.mutedText)
                Text(uiLanguage == .vi
                     ? "Sau khi cài, khởi động lại Claude Code."
                     : "After installing, restart Claude Code.")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(ReflectionTheme.mutedText)
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func manualStepCard(number: String, title: String, description: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number)
                    .font(.pixelSystem(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .pixelBox(
                        fill: ReflectionTheme.accent,
                        shadowOffset: 1,
                        blockSize: 1,
                        steps: 1,
                        borderWidth: 1
                    )
                Text(title)
                    .font(.pixelSystem(size: 14, weight: .semibold))
                    .foregroundColor(ReflectionTheme.primaryText)
            }
            Text(description)
                .font(.pixelSystem(size: 12))
                .foregroundColor(ReflectionTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            codeBlock(code)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: ReflectionTheme.accent.opacity(0.12), borderColor: ReflectionTheme.accent,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    private func codeBlock(_ code: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(code)
                .font(ReflectionTheme.mono(11))
                .foregroundColor(ReflectionTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            CopyButton(text: code)
        }
        .padding(12)
        // The step card already provides the framed container, so the code sits
        // on a soft rounded surface with just a hairline — no second pixel border
        // competing with the card's, which read as busy when nested.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ReflectionTheme.accent.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ReflectionTheme.accent.opacity(0.15), lineWidth: 1)
                )
        )
    }

}

private struct CopyButton: View {
    let text: String
    @State private var copied = false
    @State private var hovered = false

    var body: some View {
        // Quiet, borderless icon — a chunky bordered button competes with the
        // code surface and reads as clutter. Subtle hover wash + a checkmark on
        // copy give all the feedback that's needed.
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(copied ? ReflectionTheme.moodCalm : ReflectionTheme.mutedText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered ? ReflectionTheme.accent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(copied ? "Copied" : "Copy")
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.18)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.18)) { copied = false }
        }
    }
}
