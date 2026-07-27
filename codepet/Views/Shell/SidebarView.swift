// codepet/Views/Shell/SidebarView.swift
import SwiftUI

/// Task SB-1 (sidebar restructure): a ~250pt left navigation column that
/// replaces the old top bar — brand/home, "New chat", the optimized "Recent"
/// thread history (was the in-chat History toggle), the Workspace nav (was the
/// top-bar tabs), and a pinned Upgrade/account footer. Native port of the
/// purple-brand mock (`scratchpad/chat-v4-sidebar.png`).
///
/// Wired in `AppShellView`, which renders this view alongside the full-width
/// `content` and owns the `collapsed` state (see the `collapsed` binding below).
struct SidebarView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    /// Collapse affordance — the real binding is hosted in `AppShellView`'s
    /// `@State sidebarCollapsed`; the chevron here just flips it (the shell then
    /// hides this view and shows a reveal button over the content).
    @Binding var collapsed: Bool

    @State private var renamingId: String?
    @State private var renameDraft = ""
    // Stamped on appear so relative times don't recompute on every re-render —
    // mirrors `ThreadListView`'s own `now`.
    @State private var now = Date()

    private var isChatBusy: Bool {
        companyStore.isCompanionTyping || companyStore.isStreaming
    }

    private var newChatGradient: LinearGradient {
        LinearGradient(colors: [CodepetTheme.accentPurple, CodepetTheme.accentPink],
                        startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            brandRow
            newChatButton
            recentSection
            Divider().padding(.horizontal, 14).padding(.vertical, 8)
            workspaceSection
            Spacer(minLength: 0)
            bottomSection
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CodepetTheme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
        }
        .onAppear { now = Date() }
    }

    // MARK: - Brand row

    private var brandRow: some View {
        HStack(spacing: 8) {
            Button {
                companyStore.selectedDeptKey = nil
                companyStore.select(.chat)
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(newChatGradient)
                        .frame(width: 22, height: 22)
                    Text("Codepet")
                        .font(CodepetTheme.pixel(16))
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button { collapsed.toggle() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
    }

    // MARK: - New chat

    private var newChatButton: some View {
        Button {
            companyStore.newChat()
            companyStore.select(.chat)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text(lang == .vi ? "Đoạn chat mới" : "New chat")
                    .font(CodepetTheme.inter(13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(newChatGradient)
                    .opacity(isChatBusy ? 0.5 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isChatBusy)
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    // MARK: - Recent (optimized History)

    private struct ThreadBucket: Identifiable {
        let id: String
        let label: String
        let threads: [ChatThread]
    }

    /// `sortThreadsByRecent` newest-first, then grouped into Today / Yesterday /
    /// Earlier by comparing each thread's `updatedAt` day against now.
    private var groupedThreads: [ThreadBucket] {
        let sorted = sortThreadsByRecent(companyStore.threads)
        let cal = Calendar.current
        var today: [ChatThread] = []
        var yesterday: [ChatThread] = []
        var earlier: [ChatThread] = []
        for t in sorted {
            if cal.isDateInToday(t.updatedAt) { today.append(t) }
            else if cal.isDateInYesterday(t.updatedAt) { yesterday.append(t) }
            else { earlier.append(t) }
        }
        var buckets: [ThreadBucket] = []
        if !today.isEmpty {
            buckets.append(ThreadBucket(id: "today", label: lang == .vi ? "Hôm nay" : "Today", threads: today))
        }
        if !yesterday.isEmpty {
            buckets.append(ThreadBucket(id: "yesterday", label: lang == .vi ? "Hôm qua" : "Yesterday", threads: yesterday))
        }
        if !earlier.isEmpty {
            buckets.append(ThreadBucket(id: "earlier", label: lang == .vi ? "Trước đó" : "Earlier", threads: earlier))
        }
        return buckets
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(lang == .vi ? "Gần đây" : "Recent")
            if groupedThreads.isEmpty {
                Text(lang == .vi ? "Chưa có đoạn chat nào." : "No chats yet.")
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedThreads) { bucket in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.label.uppercased())
                                    .font(CodepetTheme.inter(9, weight: .medium))
                                    .foregroundColor(CodepetTheme.mutedText.opacity(0.75))
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 2)
                                ForEach(bucket.threads) { threadRow($0) }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        let isActive = thread.id == companyStore.activeThreadId
        return Group {
            if renamingId == thread.id {
                HStack(spacing: 6) {
                    TextField(lang == .vi ? "Đổi tên đoạn chat" : "Rename chat", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(CodepetTheme.inter(12))
                        .onSubmit { commitRename(thread.id) }
                    Button(lang == .vi ? "Lưu" : "Save") { commitRename(thread.id) }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            } else {
                HStack(spacing: 4) {
                    Button {
                        companyStore.switchThread(thread.id)
                        companyStore.select(.chat)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(thread.title ?? (lang == .vi ? "Đoạn chat mới" : "New chat"))
                                .font(CodepetTheme.inter(12, weight: isActive ? .semibold : .regular))
                                .foregroundColor(CodepetTheme.primaryText)
                                .lineLimit(1)
                            Text(relativeTime(thread.updatedAt, now: now))
                                .font(CodepetTheme.inter(10))
                                .foregroundColor(CodepetTheme.mutedText.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isChatBusy)

                    Menu {
                        Button {
                            renameDraft = thread.title ?? ""
                            renamingId = thread.id
                        } label: {
                            Label(lang == .vi ? "Đổi tên" : "Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            companyStore.deleteThread(thread.id)
                        } label: {
                            Label(lang == .vi ? "Xóa" : "Delete", systemImage: "trash")
                        }
                        .disabled(isChatBusy)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    // .button + .plain (not .borderlessButton) so macOS doesn't
                    // append a system disclosure chevron next to the ellipsis —
                    // same fix as the composer menus (df83ef8).
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .frame(width: 18)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isActive ? CodepetTheme.accentPurple.opacity(0.1) : Color.clear))
        .padding(.horizontal, 8)
    }

    private func commitRename(_ id: String) {
        companyStore.renameThread(id, title: renameDraft)
        renamingId = nil
    }

    // MARK: - Workspace (was the top-bar tabs)

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel(lang == .vi ? "Không gian" : "Workspace")
                .padding(.bottom, 4)
            ForEach(AppView.navTabs) { v in workspaceRow(v) }
        }
    }

    private func workspaceRow(_ v: AppView) -> some View {
        let on = companyStore.view == v
        let count = tabCount(v)
        return Button {
            companyStore.selectedDeptKey = nil
            companyStore.select(v)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: v.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundColor(on ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                Text(v.title(lang))
                    .font(CodepetTheme.inter(13, weight: on ? .semibold : .regular))
                    .foregroundColor(on ? CodepetTheme.primaryText : CodepetTheme.bodyText)
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? CodepetTheme.accentPurple.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func tabCount(_ v: AppView) -> Int {
        switch v {
        case .tasks:       return TopbarCounts.tasks(companyStore.company.tasks)
        case .library:     return TopbarCounts.library(companyStore.company.library)
        case .environment: return TopbarCounts.envPending(enabled: companyStore.company.enabledTools)
        default:           return 0
        }
    }

    // MARK: - Bottom: Upgrade card + account row

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            upgradeCard
            HStack(spacing: 8) {
                AccountMenuView()
                Spacer(minLength: 4)
                wakeButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var upgradeCard: some View {
        Button { companyStore.select(.billing) } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang == .vi ? "Nâng cấp Pro" : "Upgrade to Pro")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(lang == .vi ? "Thêm credit, mọi phòng ban." : "More credits, all departments.")
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Text(lang == .vi ? "Nâng cấp" : "Upgrade")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(newChatGradient))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodepetTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CodepetTheme.hairline))
            )
        }
        .buttonStyle(.plain)
    }

    private var wakeButton: some View {
        Button { companyStore.select(.environment) } label: {
            Text("⚡")
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .background(Circle().fill(CodepetTheme.accentOrange.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.inter(10, weight: .semibold))
            .foregroundColor(CodepetTheme.mutedText)
            .padding(.horizontal, 14)
    }
}

#if DEBUG
private struct SidebarPreviewHost: View {
    @State private var collapsed = false
    var body: some View {
        SidebarView(collapsed: $collapsed)
            .environmentObject(CompanyStore())
            .environmentObject(AppState())
            .environmentObject(AuthManager())
            .frame(height: 760)
    }
}

#Preview("SidebarView") { SidebarPreviewHost() }
#endif
