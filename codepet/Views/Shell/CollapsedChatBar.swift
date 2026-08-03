// codepet/Views/Shell/CollapsedChatBar.swift
import SwiftUI

/// The collapsed copilot: a slim composer strip along the bottom of the content
/// area, replacing the old 44pt full-height reopen rail.
///
/// The rail spent ~880pt of height on a single 15pt glyph, and — filled with
/// `CodepetTheme.surface` over `pageBackground`, two near-identical values in dark
/// mode — barely read as a control at all (the same defect the wake pill had).
/// A founder who wants chat wants to *type*, so the collapsed state is now an
/// input, not a door: the content keeps its full width and the cursor is one
/// click from the thought.
///
/// Two deliberate non-duplications:
/// - It binds the SAME `companyStore.chatDraft` the dock's `ChatComposer` uses, so
///   text typed here is already in the composer when the dock expands. Nothing is
///   copied, carried or lost.
/// - Submitting calls `companyStore.sendChat` — the same call
///   `CopilotChatView.send()` makes — so there is exactly one send path. Plan and
///   Build modes stay in the full composer; this bar is an Ask surface.
struct CollapsedChatBar: View {
    let accent: Color
    let companionName: String
    /// Work waiting on the founder, from `CollapsedChatBarState.needsYouCount`.
    let needsYou: Int
    /// A reply or run landed while the dock was closed.
    let unread: Bool
    /// Open the dock (also bound to ⌘B in `AppShellView`).
    let onExpand: () -> Void

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @FocusState private var focused: Bool

    private var busy: Bool {
        companyStore.isCompanionTyping || companyStore.isStreaming || companyStore.isFanningOut
    }
    private var canSend: Bool {
        CollapsedChatBarState.canSend(draft: companyStore.chatDraft, busy: busy)
    }
    private var placeholder: String {
        lang == .vi ? "Hỏi \(companionName) bất cứ điều gì…" : "Ask \(companionName) anything…"
    }
    private var openLabel: String {
        lang == .vi ? "Mở trợ lý (⌘B)" : "Open copilot (⌘B)"
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $companyStore.chatDraft)
                .textFieldStyle(.plain)
                .font(CodepetTheme.inter(14))
                .lineLimit(1)
                .focused($focused)
                .onSubmit(submit)

            if needsYou > 0 {
                needsYouBadge
            } else if unread {
                unreadDot
            }
            trailingButton
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        // Matches the dock composer's treatment (surface fill + accent stroke that
        // brightens on focus), at strip scale — so collapsing the dock changes the
        // composer's PLACE, not its identity.
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(CodepetTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(accent.opacity(focused ? 0.9 : 0.45), lineWidth: focused ? 1.5 : 1.2)
        )
        .codepetShadow(CodepetTheme.floatingShadow)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    /// Count of what needs the founder — gold, matching the top-nav badges so a
    /// count means the same thing wherever it appears. Tapping opens the dock.
    private var needsYouBadge: some View {
        Button(action: onExpand) {
            Text("\(needsYou)")
                .font(CodepetTheme.inter(10, weight: .semibold))
                .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentGold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(CodepetTheme.accentGold))
        }
        .buttonStyle(.plain)
        .help(lang == .vi ? "\(needsYou) việc đang chờ bạn" : "\(needsYou) waiting on you")
    }

    /// Quiet signal that something arrived while the dock was shut. No count —
    /// the point is only "there is something new", which the dock then shows.
    private var unreadDot: some View {
        Circle().fill(accent).frame(width: 7, height: 7)
            .help(lang == .vi ? "Có tin mới trong trợ lý" : "New in the copilot")
    }

    /// One control, two honest states: with text it sends, empty it opens the dock.
    /// Avoids a decorative second affordance for what is really the same intent.
    private var trailingButton: some View {
        Button(action: canSend ? submit : onExpand) {
            Image(systemName: canSend ? "arrow.up" : "bubble.left.and.bubble.right")
                .font(.system(size: canSend ? 13 : 14, weight: .semibold))
                .foregroundColor(canSend ? CodepetTheme.onAccent(accent) : accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(canSend ? accent : Color.clear))
        }
        .buttonStyle(.plain)
        .help(canSend ? (lang == .vi ? "Gửi" : "Send") : openLabel)
    }

    /// Send through the store (same path as the dock) and open the dock so the
    /// reply is visible — sending into a closed panel would be a dead end.
    private func submit() {
        let text = companyStore.chatDraft
        guard CollapsedChatBarState.canSend(draft: text, busy: busy) else { return }
        companyStore.chatDraft = ""
        onExpand()
        Task {
            await companyStore.sendChat(ChatMode.ask.shape(text, language: lang),
                                        language: lang, department: nil)
        }
    }
}

#if DEBUG
#Preview("CollapsedChatBar") {
    VStack {
        Spacer()
        CollapsedChatBar(accent: CodepetTheme.accentOrange, companionName: "Crash",
                         needsYou: 2, unread: false, onExpand: {})
    }
    .frame(width: 900, height: 220)
    .background(CodepetTheme.pageBackground)
    .environmentObject(CompanyStore())
}
#endif
