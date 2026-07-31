// codepet/Views/Company/CompanyView.swift
import SwiftUI

/// The web CompanyView — mission control. Every department is one big scannable
/// card (`.deptrow`): a full-height cover panel taking 40% of the card, then the
/// name + status pill + current task, then the to-do count on the right. Numbers
/// come straight from the web's `.deptrow` / `.dr-*` rules.
struct CompanyView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    let onOpen: (String) -> Void

    @State private var hovered: String?

    private var isDark: Bool { scheme == .dark }

    private var summaries: [DepartmentSummary] {
        DepartmentCatalog.summaries(tasks: companyStore.company.tasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.viewHeadPadding()
            // The cover panel is 40% of the card (web `flex: 0 0 40%`), which SwiftUI
            // can't express as a flex basis — measure the list width once and pass the
            // resolved cover width down to every row.
            GeometryReader { geo in
                let cardWidth = max(0, geo.size.width - 52)   // 26pt gutter each side
                ScrollView {
                    // web `.deptlist { gap: 18px; padding: 18px 26px 44px }`
                    VStack(spacing: 18) {
                        ForEach(summaries) { s in row(s, coverWidth: cardWidth * 0.40) }
                    }
                    .padding(.top, 18).padding(.horizontal, 26).padding(.bottom, 44)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // web `.vhead.vhead-row` — title block left, "Re-plan" pinned right, top-aligned.
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Công ty của bạn" : "Your company")
                    .font(CodepetTheme.inter(28, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(CodepetTheme.primaryText)
                Text(subtitle)
                    .font(CodepetTheme.inter(15))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            Spacer()
            replanButton
        }
    }

    // web `.replan { font-size: 12.5px; weight 500; radius 9; padding 8px 14px }`
    private var replanButton: some View {
        Button {
            Task { await companyStore.generateRoadmap(language: lang) }
        } label: {
            Text(replanLabel)
                .font(CodepetTheme.inter(12.5, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CodepetTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(CodepetTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(companyStore.isGeneratingRoadmap)
        .help(lang == .vi ? "Lập lại theo giai đoạn" : "Regenerate for your stage")
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

    // MARK: - One department card

    private func row(_ s: DepartmentSummary, coverWidth: CGFloat) -> some View {
        let later = s.status == .later
        let isHover = hovered == s.department.key
        let rc = s.department.accent   // web's per-row --rc
        return Button { onOpen(s.department.key) } label: {   // web opens dormant depts too (empty list)
            HStack(spacing: 0) {
                cover(s)
                    .frame(width: coverWidth)   // web `.dr-img { flex: 0 0 40% }`
                body(s)
                right(s, rc: rc, isHover: isHover)
            }
            // web `.deptrow { min-height: 200px; border-radius: 20px }`
            .frame(minHeight: 200)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CodepetTokens.cardRaised))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                // hover recolours the edge toward the row's own hue (color-mix 50%)
                .stroke(isHover ? rc.opacity(0.5) : CodepetTokens.cardEdge, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: (isHover ? CodepetTokens.shadowM(isDark) : CodepetTokens.shadowS(isDark)).color,
                    radius: isHover ? CodepetTokens.shadowM(isDark).radius : CodepetTokens.shadowS(isDark).radius,
                    y: isHover ? CodepetTokens.shadowM(isDark).y : CodepetTokens.shadowS(isDark).y)
            .offset(y: isHover ? -2 : 0)   // web `transform: translateY(-2px)`
            // web `.deptrow.later { opacity: .5 }`, dimmed less in dark (.72), and
            // hover lifts a dormant row back to .72 in both themes.
            .opacity(later ? (isDark || isHover ? 0.72 : 0.5) : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovered = h ? s.department.key : nil } }
    }

    /// web `.dr-img` — the cover fills a 40%-wide, full-height panel with the
    /// department badge pinned bottom-left (14pt in).
    private func cover(_ s: DepartmentSummary) -> some View {
        GeometryReader { geo in
            Image(s.department.coverAsset)
                .resizable().interpolation(.high).scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(s.department.ab)
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            // web: color-mix(in srgb, var(--rc) 34%, #0b0a12)
                            .fill(Color(hex: "#0b0a12").opacity(0.82))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(s.department.accent.opacity(0.34))))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.5), radius: 3.5, y: 2)
                        .padding(14)
                }
        }
        .frame(maxHeight: .infinity)
    }

    /// web `.dr-body { padding: 26px 34px; justify-content: center }`
    private func body(_ s: DepartmentSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {   // .dr-top gap
                Text(s.department.name)
                    .font(CodepetTheme.inter(25, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(1)
                statusPill(s.status, deptAccent: s.department.accent)
            }
            Text(taskLine(s))
                .font(CodepetTheme.inter(16))
                .foregroundColor(CodepetTheme.mutedText)
                .lineLimit(1)
                .padding(.top, 12)   // .dr-task margin-top
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.vertical, 26).padding(.horizontal, 34)
    }

    /// web `.dr-right` — count over a hover-only "Open", right-aligned, centred.
    private func right(_ s: DepartmentSummary, rc: Color, isHover: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            countView(s)
            if s.status != .later {
                Text(lang == .vi ? "Mở" : "Open")
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(rc)
                    .opacity(isHover ? 1 : 0)   // web `.dr-open { opacity: 0 }`
            }
        }
        .padding(.vertical, 26).padding(.trailing, 34)
        .frame(maxHeight: .infinity)
    }

    /// web `.dr-status` — uppercase micro-pill; "needs you" wears the row's hue,
    /// ready is a fixed green, idle/later sit in the neutral well.
    private func statusPill(_ st: DepartmentStatus, deptAccent: Color) -> some View {
        let ink: Color
        let fill: Color
        switch st {
        case .attention: ink = deptAccent;               fill = deptAccent.opacity(0.13)
        case .ready:     ink = CodepetTokens.readyGreen; fill = CodepetTokens.readyGreen.opacity(0.10)
        case .idle, .later: ink = CodepetTokens.faint;   fill = CodepetTokens.well
        }
        return HStack(spacing: 6) {
            Circle().fill(ink).frame(width: 7, height: 7)
            Text(st.label(lang).uppercased())
                .font(CodepetTheme.inter(11.5, weight: .semibold))
                .tracking(0.3)
                .foregroundColor(ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Capsule().fill(fill))
        .fixedSize()
    }

    private func taskLine(_ s: DepartmentSummary) -> String {
        if s.status == .later { return lang == .vi ? "Sẽ đến sau khi bạn tiến bộ" : "Comes later as you progress" }
        return s.currentTaskTitle ?? (lang == .vi ? "Đã xong hết" : "All clear")
    }

    /// web `.dr-count` — 14px label, and the number itself is 30px (`.dr-count b`).
    private func countView(_ s: DepartmentSummary) -> Text {
        if s.status == .later {
            return Text(lang == .vi ? "Sau" : "Later")
                .font(CodepetTheme.inter(14)).foregroundColor(CodepetTokens.faint)
        }
        if s.pending == 0 {
            return Text(lang == .vi ? "Đã xong hết" : "All clear")
                .font(CodepetTheme.inter(14)).foregroundColor(CodepetTokens.faint)
        }
        return Text("\(s.pending) ")
                .font(CodepetTheme.inter(30, weight: .regular))
                .foregroundColor(CodepetTheme.bodyText)
             + Text(lang == .vi ? "việc" : "to do")
                .font(CodepetTheme.inter(14)).foregroundColor(CodepetTokens.faint)
    }
}
