import SwiftUI

/// Profile → "How you've grown": the permanent, accumulating record of the
/// **agency axis**, driven by `TrajectoryDetector` over the banked
/// `AgencySignal` log. Risen patterns read "Now a strength"; still-open edges
/// read "In progress". It pairs with the **comprehension axis** (mastered
/// Dictionary terms) in a two-axis strip, so both halves of the Learner Model
/// are visible in one place.
///
/// Hidden entirely until there's something real to show — so it's silent before
/// the server `growth_signals` contract is deployed and before enough sessions
/// accumulate.
struct ProfileGrowthSection: View {

    @EnvironmentObject var agencyLog: AgencySignalLog
    @EnvironmentObject var dictionaryStore: ProjectDictionaryStore
    @Environment(\.uiLanguage) private var uiLanguage

    private let ink = Color(hex: "#2D2B26")
    private var agency: Color { CodepetTheme.accentPurple }
    private var comp: Color { CodepetTheme.accentTeal }

    // MARK: - Data

    private var trajectories: [Trajectory] {
        TrajectoryDetector.detectAll(signals: agencyLog.signals)
    }

    private var masteredCount: Int {
        dictionaryStore.entries.values.filter { $0.evolution == "mastered" }.count
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String
        let risen: Bool
        let date: Date
    }

    /// Patterns that have flipped growth → strength.
    private var risenRows: [Row] {
        trajectories.map { t in
            Row(
                id: t.id,
                title: dimensionLabel(t.signal),
                detail: uiLanguage == .vi
                    ? "trước là điểm yếu trong \(t.earlierGrowthCount) buổi · giờ làm đều"
                    : "was a growth edge in \(t.earlierGrowthCount) early sessions · now done as you go",
                risen: true,
                date: t.lastSeen
            )
        }
    }

    /// Dimensions still showing an open growth edge (latest signal is a growth)
    /// and not yet risen — "what byte is still watching."
    private var inProgressRows: [Row] {
        let risenDims = Set(trajectories.map(\.signal))
        var byDim: [String: [AgencySignal]] = [:]
        for s in agencyLog.signals { byDim[s.signal.lowercased(), default: []].append(s) }

        var rows: [Row] = []
        for (dim, group) in byDim where !risenDims.contains(dim) {
            guard let latest = group.max(by: { $0.createdAt < $1.createdAt }), latest.isGrowth
            else { continue }
            rows.append(Row(
                id: "\(dim)__prog",
                title: dimensionLabel(dim),
                detail: latest.observation,
                risen: false,
                date: latest.createdAt
            ))
        }
        return rows.sorted { $0.date > $1.date }
    }

    /// Human label for a process dimension.
    private func dimensionLabel(_ signal: String) -> String {
        switch AgencySignal.Signal(rawValue: signal.lowercased()) {
        case .scoping:      return uiLanguage == .vi ? "Chia nhỏ công việc đúng cỡ" : "Scoping tasks to the right size"
        case .prompting:    return uiLanguage == .vi ? "Ra lệnh cho AI rõ ràng" : "Prompting clearly"
        case .verification: return uiLanguage == .vi ? "Kiểm tra kết quả của AI" : "Checking the AI's output"
        case .direction:    return uiLanguage == .vi ? "Dẫn dắt thay vì làm theo" : "Steering instead of accepting"
        case .iteration:    return uiLanguage == .vi ? "Xoay xở khi bí" : "Recovering when stuck"
        case .context:      return uiLanguage == .vi ? "Cung cấp đúng ngữ cảnh" : "Giving the AI the right context"
        case .none:         return signal.capitalized
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    // MARK: - Body

    var body: some View {
        let risen = risenRows
        let inProgress = inProgressRows
        if risen.isEmpty && inProgress.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(uiLanguage == .vi ? "Sự tiến bộ của bạn" : "How you've grown")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ink.opacity(0.65))
                    .tracking(0.5)
                    .textCase(.uppercase)

                axisStrip
                growthCard(rows: risen + inProgress)
            }
        }
    }

    // MARK: - Two-axis strip

    private var axisStrip: some View {
        HStack(spacing: 12) {
            axisCard(accent: comp,
                     label: uiLanguage == .vi ? "Hiểu biết · bạn có hiểu không" : "Comprehension · do you understand it",
                     number: masteredCount,
                     desc: uiLanguage == .vi ? "từ đã thành thạo, từ code của bạn" : "terms mastered, from your code")
            axisCard(accent: agency,
                     label: uiLanguage == .vi ? "Chủ động · cách bạn dẫn dắt AI" : "Agency · how you direct the AI",
                     number: risenRows.count,
                     desc: uiLanguage == .vi ? "thói quen đã lên cấp, từ các buổi làm" : "habits leveled up, from your sessions")
        }
    }

    private func axisCard(accent: Color, label: String, number: Int, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(number)")
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(accent)
            Text(desc)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: accent.opacity(0.12), borderColor: accent,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    // MARK: - Growth list

    private func growthCard(rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text(uiLanguage == .vi ? "dựa trên cách bạn làm, không phải bài kiểm tra" : "based on how you've worked, not a quiz")
                    .font(.system(size: 11))
                    .foregroundColor(ink.opacity(0.45))
            }
            .padding(.bottom, 2)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                growRow(row)
                if index < rows.count - 1 {
                    Rectangle().fill(ink.opacity(0.10)).frame(height: 1)
                }
            }
        }
        .padding(16)
        .pixelBox(fill: agency.opacity(0.06), borderColor: agency,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    private func growRow(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            rowIcon(risen: row.risen)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(ink)
                Text(row.detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(ink.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                pill(risen: row.risen)
                Text(Self.dateFmt.string(from: row.date))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(ink.opacity(0.4))
            }
        }
        .padding(.vertical, 12)
    }

    private func rowIcon(risen: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(risen ? agency : Color.clear)
            if !risen {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(agency.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
            }
            Image(systemName: risen ? "diamond.fill" : "circle")
                .font(.system(size: risen ? 9 : 7, weight: .bold))
                .foregroundColor(risen ? .white : agency)
        }
        .frame(width: 26, height: 26)
    }

    private func pill(risen: Bool) -> some View {
        Text(risen
             ? (uiLanguage == .vi ? "Đã thành thạo" : "Now a strength")
             : (uiLanguage == .vi ? "Đang tiến bộ" : "In progress"))
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .foregroundColor(risen ? .white : agency)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(risen ? agency : agency.opacity(0.14)))
    }
}
