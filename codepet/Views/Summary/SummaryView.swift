// codepet/Views/Summary/SummaryView.swift
import SwiftUI

/// The Summary digest — a value-first recap of what Codepet has done for the
/// founder, composed CLIENT-SIDE from `company` (roadmap + library). Read-only:
/// never mutates the store. Mirrors the web SummaryView's fallback path (hero,
/// autopilot bar, stat chips, recent wins). Live Claude-Code session/commit
/// tracking is a separate subsystem and intentionally out of scope.
struct SummaryView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var data: SummaryData { SummaryData(company: companyStore.company, language: lang) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                autopilotBar
                statChips
                recentWins
            }
            .padding(18)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Hero
    private var hero: some View {
        let d = data
        return CodepetCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(d.isAllClear
                     ? (lang == .vi ? "Mọi thứ ổn — Byte đang rảnh ✨"
                                    : "All clear — Byte has nothing on its plate right now ✨")
                     : (lang == .vi ? "Byte đang chạy \(d.byteHandled) việc cho bạn 🙌"
                                    : "Byte's on a roll — running \(d.byteHandled) \(d.byteHandled == 1 ? "task" : "tasks") for you 🙌"))
                    .font(.pixelSystem(size: 18, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi
                     ? "\(d.doneCount)/\(d.totalCount) việc · \(d.departmentCount) phòng ban"
                     : "\(d.doneCount)/\(d.totalCount) tasks moved · \(d.departmentCount) departments")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Autopilot bar
    private var autopilotBar: some View {
        let d = data
        let active = max(1, d.byteHandled + d.needsYou)
        let tealFrac = (d.byteHandled == 0 && d.needsYou == 0) ? 1.0 : Double(d.byteHandled) / Double(active)
        return CodepetCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(d.autopilotPct)%")
                            .font(.pixelSystem(size: 22, weight: .bold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(lang == .vi ? "tự động" : "on autopilot")
                            .font(.pixelSystem(size: 11, weight: .medium))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        legendRow(color: CodepetTheme.accentTeal,
                                  text: lang == .vi ? "Byte lo \(d.byteHandled)" : "Byte handles \(d.byteHandled)")
                        legendRow(color: CodepetTheme.accentGold,
                                  text: lang == .vi ? "bạn tham gia \(d.needsYou)" : "you weigh in on \(d.needsYou)")
                    }
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(CodepetTheme.accentTeal)
                            .frame(width: geo.size.width * tealFrac)
                        Rectangle().fill(CodepetTheme.accentGold)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.pixelSystem(size: 11, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
        }
    }

    // MARK: Stat chips
    private var statChips: some View {
        let d = data
        return HStack(spacing: 10) {
            statChip(value: "\(d.departmentCount)", label: lang == .vi ? "phòng ban" : "departments")
            statChip(value: "\(d.doneCount)", emphasis: "/\(d.totalCount)", label: lang == .vi ? "việc xong" : "tasks done")
            statChip(value: "\(d.shippedCount)", label: lang == .vi ? "đã giao" : "shipped & saved")
        }
    }

    private func statChip(value: String, emphasis: String? = nil, label: String) -> some View {
        CodepetCard {
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value).font(.pixelSystem(size: 20, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                    if let emphasis {
                        Text(emphasis).font(.pixelSystem(size: 12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                    }
                }
                Text(label).font(.pixelSystem(size: 10, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Recent wins
    private var recentWins: some View {
        let d = data
        return CodepetCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(lang == .vi ? "Thành quả gần đây" : "Recent wins")
                        .font(.pixelSystem(size: 14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if d.shippedCount > 0 {
                        Text("\(d.shippedCount)")
                            .font(.pixelSystem(size: 10, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(CodepetTheme.accentGold))
                    }
                }
                if d.recentWins.isEmpty {
                    Text(lang == .vi
                         ? "Chưa có gì được giao — duyệt một bản nháp và thành quả sẽ xuất hiện ở đây."
                         : "Nothing shipped yet — approve a draft and your wins land here.")
                        .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
                } else {
                    ForEach(d.recentWins) { w in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(CodepetTheme.accentTeal)
                            Text(w.title).font(.pixelSystem(size: 13, weight: .medium)).foregroundColor(CodepetTheme.primaryText)
                            Spacer()
                            Text(w.meta).font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
