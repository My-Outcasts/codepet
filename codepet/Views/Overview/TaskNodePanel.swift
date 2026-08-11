// codepet/Views/Overview/TaskNodePanel.swift
import SwiftUI

/// What a roadmap node MEANS — adapted from Cofounder's tech-tree node view. Content is derived
/// by `RoadmapNodeDetail`; this view only lays it out, so the wording stays unit-tested.
struct TaskNodePanel: View {
    let task: RoadmapTask
    let accent: Color
    /// Run the node's primary action (the caller routes it through `RoadmapDispatch`).
    let onAction: (RoadmapTask) -> Void
    /// Flip the task's done flag — "I already did this", and its undo.
    let onMarkDoneToggle: (RoadmapTask) -> Void

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    /// Rebuilt from the live task set, so approving or marking done updates the open panel.
    private var detail: RoadmapNodeDetail {
        RoadmapNodeDetail.build(for: liveTask, in: tasks, lang: lang)
    }
    /// The task as it currently exists in the store — the value passed in can go stale while the
    /// panel is open (a run finishes, a draft lands).
    private var liveTask: RoadmapTask { tasks.first { $0.id == task.id } ?? task }
    private var isRunning: Bool { companyStore.runningTaskIds.contains(task.id) }
    /// A hand-marked-done task (mark-complete, never a real run) has no library item —
    /// `RoadmapEngine.deliverable` resolves nil for it. The primary button's label for `.done`
    /// is "Open the result", so offering it here is a guaranteed dead end: it dismisses the
    /// panel and opens nothing. Hidden rather than disabled so the footer doesn't carry a
    /// button that can never do anything.
    private var primaryActionIsDeadEnd: Bool {
        liveTask.done && RoadmapEngine.deliverable(for: liveTask, in: companyStore.company.library) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(lang == .vi ? "ĐIỀU GÌ THÀNH THẬT" : "WHAT BECOMES TRUE") {
                        Text(detail.becomesTrue)
                    }
                    section(lang == .vi ? "LÀM SAO ĐỂ TIẾN LÊN" : "HOW TO MOVE THIS FORWARD") {
                        Text(detail.howToMoveForward)
                    }
                    section(lang == .vi ? "THẾ NÀO LÀ XONG" : "TO COMPLETE") {
                        Text(detail.toComplete)
                    }
                    if !detail.requiredFirst.isEmpty {
                        section(lang == .vi ? "CẦN TRƯỚC" : "REQUIRED FIRST") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(detail.requiredFirst) { requirementRow($0) }
                            }
                        }
                    }
                    if !detail.unlocks.isEmpty {
                        section(lang == .vi ? "MỞ KHOÁ" : "UNLOCKS") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(detail.unlocks, id: \.self) { title in
                                    Text("• \(title)")
                                }
                            }
                        }
                    }
                }
                .font(CodepetTheme.inter(12.5))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.vertical, 18)
            }
            footer
        }
        .frame(width: 460, height: 560)
        .background(CodepetTheme.pageBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(detail.phaseLabel)
                    .font(CodepetTheme.inter(10)).tracking(1.4)
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(CodepetTokens.well))
                if let dept = detail.deptName {
                    Text(dept).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                Spacer()
                statusPill
                closeButton
            }
            Text(detail.title)
                .font(CodepetTheme.inter(19, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
    }

    /// The way out that does nothing else.
    ///
    /// Until this existed there wasn't one. The panel is a `.sheet`, so on macOS Esc does not
    /// dismiss it and there is no backdrop to click; the only exits were the two footer buttons,
    /// and both COMMIT — one starts the task, the other marks it done. Opening a node to read
    /// what it wants and then backing out was not a thing the panel allowed. Founder report,
    /// Aug 11, with a screenshot of a panel she could not close.
    ///
    /// Worse, the footer can be empty. The primary button hides itself when it would be a dead
    /// end (`done` with no library deliverable) and mark-done hides on a `drafted` task — a task
    /// that is both shows a panel with NO buttons at all. That state was unescapable, and it is
    /// the reason this carries `.cancelAction` as well: Esc works even if the footer is bare.
    ///
    /// Placed after the status pill rather than in the footer deliberately — every control in
    /// that row changes the founder's roadmap, and a control that changes nothing does not
    /// belong among them.
    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(CodepetTheme.mutedText)
                .frame(width: 22, height: 22)
                // The tappable area is the 22pt square, not the glyph: an 10pt "×" is a
                // frustrating target, and the same `.stroke`-isn't-hit-testable lesson the
                // mark-done button records below applies to a bare Image too.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help(lang == .vi ? "Đóng" : "Close")
        .accessibilityLabel(lang == .vi ? "Đóng" : "Close")
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            if isRunning { ProgressView().controlSize(.mini) }
            if detail.status == .blocked && !isRunning {
                Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
            }
            Text(isRunning ? RoadmapBoardCopy.inProgress(lang) : detail.status.label(lang))
        }
        .font(CodepetTheme.inter(11, weight: .medium))
        .foregroundColor(taskStatusTint(detail.status))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill(taskStatusTint(detail.status).opacity(0.12)))
    }

    @ViewBuilder
    private func requirementRow(_ r: NodeRequirement) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: r.satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(r.satisfied ? RoadmapPalette.done : CodepetTheme.mutedText)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).foregroundColor(CodepetTheme.primaryText)
                if let note = r.statusNote {
                    Text(note).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            footerButtons
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(CodepetTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            if !primaryActionIsDeadEnd {
                Button {
                    dismiss()
                    onAction(liveTask)
                } label: {
                    Text(RoadmapBoardCopy.panelActionLabel(for: detail.status, lang))
                        .font(CodepetTheme.inter(12.5, weight: .bold))
                        .foregroundColor(CodepetTheme.onAccent(accent))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .opacity(isRunning ? 0.45 : 1)
            }

            // A drafted task's correct action is Approve; marking it done here would silently
            // discard generated work, so the affordance hides itself.
            if !liveTask.drafted {
                Button {
                    onMarkDoneToggle(liveTask)
                } label: {
                    Text(liveTask.done ? RoadmapBoardCopy.markNotDone(lang)
                                       : RoadmapBoardCopy.markComplete(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .stroke(CodepetTheme.hairline, lineWidth: 1))
                        // `.stroke` fills the 1pt outline and nothing else, so the ring between
                        // the label and the border was not hit-testable: a click 6pt inside the
                        // border, right next to the word, did nothing. The primary button beside
                        // it never had this problem because its background is a real `.fill`.
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                // Guards the same failure the primary button guards: an in-flight run can land
                // its draft (`drafted = true`) right after mark-done sets `done = true`, and
                // `status` short-circuits on `done` before ever consulting `drafted` — stranding
                // the generated deliverable with no way to reach it. Blocking the tap while
                // `isRunning` closes that window.
                .disabled(isRunning)
                .opacity(isRunning ? 0.45 : 1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1.2)
                .foregroundColor(CodepetTheme.mutedText)
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
/// Hosts the panel against a store seeded with one task, so both states below are the real view
/// rather than a mock of it.
private struct TaskNodePanelPreviewHost: View {
    let task: RoadmapTask
    @StateObject private var store: CompanyStore

    init(task: RoadmapTask) {
        self.task = task
        // Seeded through the LOADER rather than by assigning `company` (its setter is
        // private(set) — the store owns its state and only hydrate/mutators may write it),
        // which is also how the test suites build a store.
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                  stage: .idea, companionId: "byte", onboardedAt: Date(),
                                  tasks: [task])
        _store = StateObject(wrappedValue: CompanyStore(loader: { _ in seeded },
                                                        saver: { _, _ in true }))
    }

    var body: some View {
        TaskNodePanel(task: task, accent: CodepetTheme.accentPurple,
                      onAction: { _ in }, onMarkDoneToggle: { _ in })
            .environmentObject(store)
            .task { await store.hydrate(companyId: "preview") }
    }
}

#Preview("Task panel — ordinary") {
    TaskNodePanelPreviewHost(task: RoadmapTask(
        id: "t1", title: "Test willingness to pay",
        detail: "Run a real price conversation, pre-order, or fake door with target users.",
        phase: .foundation, who: .you, dept: "fin"))
}

/// THE TRAP STATE, kept as a preview because it is the reason Esc is wired and it cannot be
/// reached by clicking around: `done` with no library deliverable hides the primary button
/// (it would be a dead end), and `drafted` hides mark-done. The footer renders EMPTY. Before
/// the close button this panel had no exit at all — check that the × is present and that Esc
/// dismisses it.
#Preview("Task panel — empty footer (the trap)") {
    TaskNodePanelPreviewHost(task: RoadmapTask(
        id: "t2", title: "A task with nothing left to press",
        detail: "Done, drafted, and holding no deliverable to open.",
        phase: .foundation, who: .does, done: true, drafted: true, dept: "eng"))
}
#endif
