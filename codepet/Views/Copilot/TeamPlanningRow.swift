import SwiftUI

/// The three waits before a Team Build has a card of its own — reading the product folder,
/// gathering the room, planning the work — drawn as ONE quiet line, not a card (6 Oct design
/// pass). Each used to be a bordered purple card with a spinner, and the typing row's
/// "Cooking…" sat under it as a second signal; the build-8 screenshots read as clutter. What
/// stays is what proves it has not stalled: a pulse and a ticking clock.
struct TeamWaitingLine: View {
    let title: String
    let detail: String
    /// Department keys whose pets sit under the line. Empty draws none.
    var pets: [String] = []
    /// Pets fade in one after another — used while the room is being chosen, where the line has
    /// nothing else that moves.
    var staggerPets = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when the line first appears; the line is removed when its wait ends.
    @State private var startedAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TeamPulseDot()
                Text(title)
                    .font(CodepetTheme.inter(13.5, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(TeamBuildCopy.clock(ctx.date.timeIntervalSince(startedAt)))
                        .font(CodepetTheme.inter(12))
                        .monospacedDigit()
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            if !pets.isEmpty {
                TimelineView(.periodic(from: startedAt, by: 0.6)) { ctx in
                    let shown = staggerPets && !reduceMotion
                        ? min(pets.count, Int(ctx.date.timeIntervalSince(startedAt) / 0.6) + 1) : pets.count
                    HStack(spacing: 6) {
                        ForEach(Array(pets.enumerated()), id: \.offset) { i, dept in
                            TeamPetAvatar(dept: dept, size: 18)
                                .opacity(i < shown ? 1 : 0)
                                .animation(.easeOut(duration: 0.35), value: shown)
                        }
                    }
                }
                .padding(.leading, 18)
            }
            Text(detail)
                .font(CodepetTheme.inter(12))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 18)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A small accent dot with a soft ring that breathes outward — the "still working" mark on every
/// quiet Team Build line. Still under Reduce Motion.
struct TeamPulseDot: View {
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Circle()
            .fill(CodepetTheme.accentPurple)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .stroke(CodepetTheme.accentPurple.opacity(breathe ? 0 : 0.5), lineWidth: 2)
                    .scaleEffect(breathe ? 2.2 : 1)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { breathe = true }
            }
            .accessibilityHidden(true)
    }
}

/// "Planning the work" while a Team Build's planner runs (`CompanyStore.isPlanningTeamBuild`).
/// Planning can take up to 180 s, and before a row existed the only sign was a greyed button.
/// The pets are the departments the room seated — none when the router sent the ask straight
/// to the planner.
struct TeamPlanningRow: View {
    var departments: [String] = []
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        let vi = lang == .vi
        TeamWaitingLine(
            title: vi ? "Đang lập kế hoạch" : "Planning the work",
            detail: departments.isEmpty
                ? (vi ? "Chia việc cho từng phòng ban, có thể mất vài phút" : "Splitting it across departments, this can take a few minutes")
                : (vi ? "Chia việc cho \(departments.count) phòng ban, có thể mất vài phút"
                      : "Splitting it across \(departments.count) department\(departments.count == 1 ? "" : "s"), this can take a few minutes"),
            pets: departments)
    }
}

/// "Reading your product folder" while `CompanyStore.isReadingProductFolder` — the one-time
/// read-only pass that writes the `ProductDossier` (about a minute and a half on the Codepet repo).
/// A Team build press waits on it, so without this row the button would look like it did nothing.
struct ProductReadingRow: View {
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        let vi = lang == .vi
        TeamWaitingLine(
            title: vi ? "Đang đọc thư mục sản phẩm" : "Reading your product folder",
            detail: vi ? "Một lần cho mỗi thư mục, để cả đội biết sản phẩm của bạn. Chỉ đọc, không sửa."
                       : "Once per folder, so the team knows your product. Read-only.")
    }
}

/// "Gathering the team" while a Team Build's router picks the room (`CompanyStore.isConveningTeamRoom`).
/// The router is its own `claude -p` call, about a minute, and the room has no card until it
/// answers — without a row a press looked frozen (CP-027). The router picks the whole room in one
/// answer, so the pets fading in are the company's team being called together, not seats
/// confirmed one by one; who actually joined shows on the room's own card.
struct TeamConveningRow: View {
    var roster: [String] = []
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        TeamWaitingLine(title: TeamBuildCopy.conveningTitle(lang),
                        detail: TeamBuildCopy.conveningDetail(lang),
                        pets: roster, staggerPets: true)
    }
}
