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
            }
            Text(detail.title)
                .font(CodepetTheme.inter(19, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
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
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(CodepetTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
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
