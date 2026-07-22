// codepet/Views/Company/CompanyView.swift
import SwiftUI

/// The web CompanyView — every department as a scannable row (cover + status +
/// current task + count). Derives per-dept summaries from the dept-tagged tasks.
struct CompanyView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    let onOpen: (String) -> Void

    private var summaries: [DepartmentSummary] {
        DepartmentCatalog.summaries(tasks: companyStore.company.tasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                VStack(spacing: 10) {
                    ForEach(summaries) { s in row(s) }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Công ty của bạn" : "Your company")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(subtitle).font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText)
            }
            Spacer()
            Button {
                Task { await companyStore.generateRoadmap(language: lang) }
            } label: {
                Text(replanLabel)
                    .font(CodepetTheme.inter(12, weight: .medium))
                    .foregroundColor(CodepetTheme.bodyText)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(CodepetTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(companyStore.isGeneratingRoadmap)
        }
    }

    private var subtitle: String {
        let n = DepartmentCatalog.needToday(summaries)
        return lang == .vi ? "Tám phòng ban · \(n) cần bạn hôm nay"
                           : "Eight departments · \(n) need you today"
    }
    private var replanLabel: String {
        companyStore.isGeneratingRoadmap
            ? (lang == .vi ? "Đang lập lại…" : "Re-planning…")
            : (lang == .vi ? "Lập lại cho giai đoạn của tôi" : "Re-plan for my stage")
    }

    private func row(_ s: DepartmentSummary) -> some View {
        let later = s.status == .later
        return Button { onOpen(s.department.key) } label: {   // web opens dormant depts too (empty list)
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    Image(s.department.coverAsset).resizable().scaledToFill()
                        .frame(width: 96, height: 64).clipped()
                        .cornerRadius(10)
                    Text(s.department.ab)
                        .font(CodepetTheme.inter(11, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(s.department.accent.opacity(0.85)).cornerRadius(6)
                        .padding(6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(s.department.name).font(CodepetTheme.sectionName())
                            .foregroundColor(CodepetTheme.primaryText)
                        statusPill(s.status, deptAccent: s.department.accent)
                    }
                    Text(taskLine(s)).font(CodepetTheme.inter(16)).foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    countView(s).foregroundColor(CodepetTheme.bodyText)
                    if !later {
                        Text(lang == .vi ? "Mở" : "Open").font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(s.department.accent)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.hairline, lineWidth: 1))
            .opacity(later ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ st: DepartmentStatus, deptAccent: Color) -> some View {
        // Web colors the "needs you" pill with the row's own department accent (--rc);
        // ready/idle/later keep their fixed status tints.
        let tint = st == .attention ? deptAccent : st.tint
        return HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(st.label(lang)).font(CodepetTheme.inter(11.5, weight: .semibold)).foregroundColor(tint)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func taskLine(_ s: DepartmentSummary) -> String {
        if s.status == .later { return lang == .vi ? "Sẽ đến sau khi bạn tiến bộ" : "Comes later as you progress" }
        return s.currentTaskTitle ?? (lang == .vi ? "Đã xong hết" : "All clear")
    }
    // Web bolds the number specifically (`<b>{pend}</b> to do`).
    private func countView(_ s: DepartmentSummary) -> Text {
        if s.status == .later { return Text(lang == .vi ? "Sau" : "Later").font(CodepetTheme.inter(14)) }
        if s.pending == 0 { return Text(lang == .vi ? "Đã xong hết" : "All clear").font(CodepetTheme.inter(14)) }
        return Text("\(s.pending)").font(CodepetTheme.inter(18, weight: .bold))
             + Text(lang == .vi ? " việc" : " to do").font(CodepetTheme.inter(14))
    }
}
