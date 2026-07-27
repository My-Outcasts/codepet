// codepet/Views/Tasks/TaskDraftPreview.swift
import SwiftUI

/// Draft-preview sheet shown when a founder taps an "Awaiting your approval" task —
/// comprehension + control BEFORE action (web parity). Instead of approving blindly,
/// this renders the generated draft (typed viewer, same as the Library) plus a Revise
/// row (the shared `ReviseKind` chips) and an Approve button. Approve is the ONLY path
/// that copies the draft into the Library.
///
/// Binds to the LIVE task in the store (looked up by id each render) rather than a
/// captured copy, so a revise re-run refreshes the body in place. The sheet is dismissed
/// only by the X or by Approve — a revise keeps it open.
struct TaskDraftPreview: View {
    let taskId: String
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.dismiss) private var dismiss
    /// True while a revise re-run (or the approve) is in flight — disables the whole
    /// action row so a mid-run tap can't race the store's guarded update.
    @State private var busy = false

    private var task: RoadmapTask? { companyStore.company.tasks.first { $0.id == taskId } }
    private var draft: Deliverable? { task?.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let d = draft {
                header(d)
                Divider()
                ScrollView { DeliverableBodyView(deliverable: d).padding(16) }
                Divider()
                actionBar
            } else {
                // The draft is gone (approved/cleared elsewhere) — nothing left to review.
                emptyState
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .background(CodepetTheme.pageBackground)
    }

    private func header(_ d: Deliverable) -> some View {
        HStack(spacing: 8) {
            Image(systemName: d.kind.icon).foregroundColor(CodepetTheme.accentPurple)
            Text(d.title)
                .font(.pixelSystem(size: 15, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
        }
        .padding(16)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        busy = true
                        await companyStore.approveTask(id: taskId)
                        busy = false
                        dismiss()
                    }
                } label: {
                    Text(lang == .vi ? "Duyệt" : "Approve")
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.mini) }
            }
            // Revise chips: one-tap targeted re-runs of THIS draft (same infra + labels
            // as the chat draft card's revise row).
            HStack(spacing: 6) {
                ForEach(ReviseKind.allCases, id: \.self) { kind in
                    Button {
                        Task {
                            busy = true
                            await companyStore.reviseTaskDraft(taskId: taskId,
                                                               reviseNote: kind.note(lang), language: lang)
                            busy = false
                        }
                    } label: {
                        Text(kind.label(lang))
                            .font(.pixelSystem(size: 9, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().stroke(CodepetTheme.hairline))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(lang == .vi ? "Không còn bản nháp để duyệt." : "No draft left to review.")
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.mutedText)
            Button { dismiss() } label: {
                Text(lang == .vi ? "Đóng" : "Close")
                    .font(.pixelSystem(size: 11, weight: .semibold))
                    .foregroundColor(CodepetTheme.bodyText)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().stroke(CodepetTheme.hairline))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
