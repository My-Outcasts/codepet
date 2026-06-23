import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tour: TourController
    @Environment(\.uiLanguage) private var uiLanguage

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        // Natural sizing — cards are content-sized, not stretched to fill the
        // viewport, so the progress cards don't tower over the stat cards.
        ScrollView {
            VStack(spacing: 20) {
                // Hero: identity (folds in Account status).
                ProfileHeroCard()

                // Key progress, surfaced right under the identity.
                ProfileStatsBento()

                // "How you've grown" — the agency-axis trajectory record + the
                // two-axis strip. Self-hides until there's real signal to show.
                ProfileGrowthSection()

                // Companion switcher + app voice, combined into one card.
                // Nudged down a little for more breathing room below the stats.
                PersonalizeSection()
                    .padding(.top, 12)

                // Re-open the character-narrated intro tour anytime.
                HStack {
                    ReplayGuideRow(character: character) { tour.start() }
                    Spacer()
                }

                // Demo toggle, tucked into the bottom-left corner.
                HStack {
                    DebugSection()
                    Spacer()
                }
            }
            .padding(20)
        }
        .background(Color(hex: "#F7F5FC"))
        .onAppear {
            // First visit to Profile after onboarding → run the spotlight tour once.
            if appState.onboardingComplete && !appState.hasSeenFeatureGuide && !tour.isActive {
                tour.start()
            }
        }
    }
}

// MARK: - Replay Guide Row
//
// A slim, functional entry point to re-open the feature guide, styled to match
// the other light tinted pixel-box rows on the profile.

private struct ReplayGuideRow: View {
    let character: PetCharacter
    let action: () -> Void
    @Environment(\.uiLanguage) private var uiLanguage

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(character.color)
                Text(uiLanguage == .vi ? "Xem lại hướng dẫn" : "Replay intro guide")
                    .font(.pixelSystem(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#2D2B26"))
            }
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .pixelBox(fill: character.color.opacity(0.10), borderColor: character.color,
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Hero Card
//
// The "personal dashboard" header: the active pet avatar, the user's name, their
// account status (signed-in / guest / signed-out, with the matching action), and
// a brand-colored stat strip surfacing the numbers a learner tracks — level,
// streak, lessons, coins — plus an XP-to-next-level bar. The card is tinted to
// the chosen pet's color so the profile feels personal.

struct ProfileHeroCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var uiLanguage

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    private var displayName: String {
        appState.displayName.isEmpty ? character.name : appState.displayName
    }

    /// Ties the user's identity to their chosen companion — the personalized
    /// touch. With a name set: "Coding with Nova · The Firestarter". Without one
    /// (name falls back to the pet), lead with the pet's badge + role instead so
    /// it doesn't read "Coding with Nova" next to a "Nova" headline.
    private var tagline: String {
        appState.displayName.isEmpty
            ? "\(character.badge) · \(character.domain)"
            : "Coding with \(character.name) · \(character.badge)"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Identity row
            HStack(spacing: 14) {
                // Static, contained portrait. The idle float/twitch + breathing
                // are built for the big Home pet scene; in this small tile they
                // just shove the sprite outside the rounded box. A fixed-size,
                // clipped tile frames every character consistently.
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(character.color.opacity(0.18))
                    CharacterImage(character.id, size: 58)
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(character.color.opacity(0.45), lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        // Standard font (not pixel) — renders names with
                        // diacritics (e.g. Vietnamese) cleanly.
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tagline)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(character.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    statusLine
                }

                Spacer()

                HStack(spacing: 8) {
                    languageMenu
                    actionButton
                }
            }
        }
        .padding(18)
        // No border or background — the identity row sits plainly on the page
        // for a simpler, lighter header.
    }

    // MARK: account status (folded in from AccountSection)

    @ViewBuilder
    private var statusLine: some View {
        if let user = authManager.currentUser, !user.isAnonymous {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#5DCAA5")).frame(width: 7, height: 7)
                Text(accountLabel(for: user))
                    .font(.pixelSystem(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                    .lineLimit(1)
            }
        } else if authManager.isGuestMode {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FCDE5A")).frame(width: 7, height: 7)
                Text(uiLanguage == .vi ? "Chế độ khách · đăng nhập để đồng bộ"
                                       : "Guest mode · sign in to sync")
                    .font(.pixelSystem(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 6) {
                Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 7, height: 7)
                Text(uiLanguage == .vi ? "Chưa đăng nhập" : "Not signed in")
                    .font(.pixelSystem(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Compact globe language switcher, sitting beside the Sign out button so
    /// language lives with the account actions instead of in a settings row.
    @ViewBuilder
    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    appState.uiLanguage = lang
                } label: {
                    if appState.uiLanguage == lang {
                        Label("\(lang.flag)  \(lang.displayName)", systemImage: "checkmark")
                    } else {
                        Text("\(lang.flag)  \(lang.displayName)")
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                .frame(width: 34, height: 34)
                .pixelBox(fill: .white, borderColor: character.color,
                          shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(uiLanguage == .vi ? "Ngôn ngữ hiển thị" : "Display language")
    }

    @ViewBuilder
    private var actionButton: some View {
        if let user = authManager.currentUser, !user.isAnonymous {
            Button(action: { authManager.signOut() }) {
                Text(uiLanguage == .vi ? "Đăng xuất" : "Sign out")
            }
            .buttonStyle(PixelButtonStyle(
                fill: Color(hex: "#E04040").opacity(0.12),
                foreground: Color(hex: "#C04040"),
                borderColor: Color(hex: "#C04040"),
                paddingH: 12, paddingV: 6, blockSize: 2, steps: 2,
                borderWidth: 2, shadowOffset: 2,
                font: .pixelSystem(size: 11, weight: .semibold)
            ))
        } else if authManager.isGuestMode {
            Button(action: { authManager.isGuestMode = false }) {
                Text(uiLanguage == .vi ? "Đăng nhập" : "Sign in")
            }
            .buttonStyle(PixelButtonStyle(
                fill: character.color,
                foreground: .white,
                paddingH: 14, paddingV: 7, blockSize: 2, steps: 2,
                borderWidth: 2, shadowOffset: 2,
                font: .pixelSystem(size: 11, weight: .semibold)
            ))
        }
    }

    private func accountLabel(for user: User) -> String {
        let who: String
        if let email = user.email, !email.isEmpty { who = email }
        else if let name = user.displayName, !name.isEmpty { who = name }
        else { who = uiLanguage == .vi ? "Đã đăng nhập" : "Signed in" }
        switch authManager.authMethod {
        case "google": return "\(who) · Google"
        case "email":  return who
        case "pin":    return "\(who) · PIN"
        default:       return who
        }
    }
}

// MARK: - Progress Bento
//
// The colorful stat cards, relocated to a full-width band at the bottom of the
// profile (was crammed into the hero). Large Level/XP card + Streak card with a
// 7-day strip + small Lessons/Coins cards.

struct ProfileStatsBento: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var challengeProgress: ChallengeProgress
    @Environment(\.uiLanguage) private var uiLanguage

    /// Agentic-coding exercises completed / available (the active learning loop).
    private var completedExercises: Int {
        challengeProgress.activeChallenges.filter {
            challengeProgress.completedChallengeIds.contains($0.id)
        }.count
    }
    private var totalExercises: Int { challengeProgress.activeChallenges.count }

    /// Drives the Duolingo-style streak detail modal (opened from the compact card).
    @State private var showStreakDetail = false
    /// Shared height for the two side-by-side cards. Tall enough for the Streak
    /// card's count row + full-width week strip, and for the Exercises card's
    /// stacked icon → count → progress bar → XP badge column.
    private let cardHeight: CGFloat = 250

    /// The dashboard tracks real data — the user's actual saved daily snapshots.
    private var calendarSnapshots: [DailySnapshot] {
        appState.dailySnapshots
    }

    var body: some View {
        // Two side-by-side cards: the Streak calendar is the main card (70%) on
        // the left, the Exercises tracker a slimmer companion (30%) on the right.
        // Both wear the light "info bar" treatment and share one height.
        VStack(alignment: .leading, spacing: 10) {
            Text(uiLanguage == .vi ? "Tiến độ của bạn" : "Your progress")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.65))
                .tracking(0.5)
                .textCase(.uppercase)

            GeometryReader { geo in
                let spacing: CGFloat = 10
                let streakWidth = (geo.size.width - spacing) * 0.7
                HStack(alignment: .top, spacing: spacing) {
                    // Main card (70%) — Streak calendar.
                    CompactStreakCard(streak: appState.streak,
                                      snapshots: calendarSnapshots,
                                      frozenDays: gameState.frozenStreakDays,
                                      action: { showStreakDetail = true })
                        .frame(width: streakWidth)

                    // Companion card (30%) — Exercises tracker. Tapping it opens
                    // the Tips tab and scrolls to the "Agentic coding skills"
                    // section, where the exercises are listed in order.
                    ProfileStatChip(accent: CodepetTheme.accentTeal, icon: "book.fill",
                                    value: "\(completedExercises)",
                                    label: "Exercises",
                                    progress: Double(completedExercises) / Double(max(1, totalExercises)),
                                    footnote: "\(completedExercises) of \(totalExercises) completed",
                                    badge: "\(appState.totalXP) XP",
                                    action: {
                                        appState.pendingScrollToSkills = true
                                        appState.selectedTab = .tips
                                    })
                        .frame(maxWidth: .infinity)
                }
                .frame(height: geo.size.height)
            }
            .frame(height: cardHeight)
        }
        .sheet(isPresented: $showStreakDetail) {
            StreakDetailView(streak: appState.streak,
                             best: appState.longestStreak,
                             freezes: gameState.streakFreezes,
                             snapshots: calendarSnapshots,
                             frozenDays: gameState.frozenStreakDays)
        }
    }
}

/// One brand-colored stat chip whose information layout mirrors the streak
/// card: an icon chip beside the big value + uppercase label with a caption
/// below, then a divider and a bottom zone holding the progress bar and an
/// optional badge (e.g. XP).
private struct ProfileStatChip: View {
    let accent: Color
    let icon: String
    let value: String
    let label: String
    /// Optional 0…1 progress bar (e.g. lessons completed / total).
    var progress: Double? = nil
    /// Caption under the bar / at the bottom of the card.
    var footnote: String? = nil
    /// Optional trailing badge (e.g. XP earned), shown top-right of the header.
    var badge: String? = nil
    /// When set, the whole card becomes a button (with a chevron affordance)
    /// that runs this on tap — e.g. jump into the next exercise.
    var action: (() -> Void)? = nil

    // Dark ink throughout — the card now sits on a light tinted background.
    private let ink = Color(hex: "#2D2B26")

    var body: some View {
        if let action = action {
            Button(action: action) { cardContent }
                .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    // Mirrors the streak card's vertical structure: a TOP summary (icon chip
    // beside the big value + label, with a caption below) and, under a
    // divider, a BOTTOM zone holding the progress bar and XP badge.
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // TOP — icon + value + label, caption beneath (like DAY STREAK).
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(ink)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(ink.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(value)
                            .font(.system(size: 48, weight: .heavy))
                            .foregroundColor(ink)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(label.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(ink.opacity(0.65))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let footnote = footnote {
                        Text(footnote)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ink.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Divider between the summary and the progress zone.
            Rectangle()
                .fill(ink.opacity(0.12))
                .frame(height: 1.5)

            // BOTTOM — progress bar stretched full width + XP badge.
            VStack(alignment: .leading, spacing: 10) {
                if let progress = progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.2))
                            Capsule()
                                .fill(ink)
                                .frame(width: max(8, geo.size.width * min(1, max(0, progress))))
                        }
                    }
                    .frame(height: 8)
                }

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(ink.opacity(0.18)))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Open affordance (top-right) when the card is tappable — mirrors the
        // streak card's chevron.
        .overlay(alignment: .topTrailing) {
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ink.opacity(0.5))
                    .padding(14)
            }
        }
        // Light "info bar" treatment: a soft tint behind a thin (2px) pixel
        // staircase border tinted to the card's own accent (not black).
        .pixelBox(fill: accent.opacity(0.12), borderColor: accent,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Account Section

struct AccountSection: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var uiLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(uiLanguage == .vi ? "Tài khoản" : "Account")
                .font(.pixelSystem(size: 14, weight: .semibold, design: .default))

            VStack(alignment: .leading, spacing: 14) {
                if let user = authManager.currentUser, !user.isAnonymous {
                    signedInBody(user)
                } else if authManager.isGuestMode {
                    guestBody
                } else {
                    notSignedInBody
                }
            }
            .padding(16)
            .pixelBox(fill: Color.white)
        }
    }

    // MARK: signed in

    @ViewBuilder
    private func signedInBody(_ user: User) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Live "online" status dot — pulsing green ring drawn manually.
            ZStack {
                Circle()
                    .fill(Color(hex: "#5DCAA5").opacity(0.20))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(Color(hex: "#5DCAA5"))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(uiLanguage == .vi ? "Đã đăng nhập" : "Signed in")
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#3F8B6E"))
                    .tracking(0.6)
                Text(displayLabel(for: user))
                    .font(.pixelSystem(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .lineLimit(1)
                if let method = methodLabel() {
                    Text(method)
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { authManager.signOut() }) {
                Text(uiLanguage == .vi ? "Đăng xuất" : "Sign out")
            }
            .buttonStyle(PixelButtonStyle(
                fill: Color(hex: "#E04040").opacity(0.12),
                foreground: Color(hex: "#C04040"),
                borderColor: Color(hex: "#C04040"),
                paddingH: 12,
                paddingV: 6,
                blockSize: 2,
                steps: 2,
                borderWidth: 2,
                shadowOffset: 2,
                font: .pixelSystem(size: 11, weight: .semibold)
            ))
        }
    }

    private func displayLabel(for user: User) -> String {
        if let email = user.email, !email.isEmpty { return email }
        if let name = user.displayName, !name.isEmpty { return name }
        return "Anonymous"
    }

    private func methodLabel() -> String? {
        switch authManager.authMethod {
        case "google": return "via Google"
        case "email":  return "via Email"
        case "pin":    return "via PIN"
        default:       return nil
        }
    }

    // MARK: guest

    private var guestBody: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FCDE5A").opacity(0.30))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(Color(hex: "#FCDE5A"))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Guest mode")
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#A37B0A"))
                    .tracking(0.6)
                Text("Sign in to sync progress and chat")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .lineLimit(2)
            }

            Spacer()

            Button(action: { authManager.isGuestMode = false }) {
                Text(uiLanguage == .vi ? "Đăng nhập" : "Sign in")
            }
            .buttonStyle(PixelButtonStyle(
                fill: Color(hex: "#7B6BD8"),
                foreground: .white,
                paddingH: 14,
                paddingV: 7,
                blockSize: 2,
                steps: 2,
                borderWidth: 2,
                shadowOffset: 2,
                font: .pixelSystem(size: 11, weight: .semibold)
            ))
        }
    }

    // MARK: signed out (edge case — routing usually keeps user on sign-in screen)

    private var notSignedInBody: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .stroke(Color.secondary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
            Text(uiLanguage == .vi ? "Chưa đăng nhập" : "Not signed in")
                .font(.pixelSystem(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Personalize Section (pet switcher + app voice — see PersonalizeSection)

private struct PetGridCell: View {
    let character: PetCharacter
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(character.color.opacity(isSelected ? 0.22 : (isHovered ? 0.14 : 0.07)))
                        .frame(height: 38)

                    CharacterImage(character.id, size: 30)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? character.color : Color.clear, lineWidth: 2)
                )

                Text(character.name)
                    .font(.pixelSystem(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? character.color : Color(hex: "#2D2B26"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Personalize Section
//
// Companion switcher + app voice, combined into ONE card (was two side-by-side
// boxes). Two labeled rows — "Your Pet" and "App voice" — split by a divider,
// sharing a single light accent pixel border.

struct PersonalizeSection: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(uiLanguage == .vi ? "Cá nhân hóa" : "Personalize")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.65))
                .tracking(0.5)
                .textCase(.uppercase)

            // All content centered within the box.
            VStack(spacing: 10) {
                // — Your Pet —
                VStack(spacing: 6) {
                    Text(uiLanguage == .vi ? "Pet của bạn" : "Your Pet")
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#2D2B26"))

                    // Centered row (matching the App voice chips below and the
                    // onboarding picker), rather than a left-packed adaptive grid.
                    HStack(spacing: 8) {
                        ForEach(PetCharacter.starters, id: \.self) { charId in
                            if let char = PetCharacter.all[charId] {
                                PetGridCell(
                                    character: char,
                                    isSelected: appState.activeChar == charId,
                                    action: {
                                        SoundManager.shared.playCharSelect()
                                        appState.activeChar = charId
                                    }
                                )
                            }
                        }
                    }
                }

                Rectangle()
                    .fill(Color(hex: "#E0DBEF"))
                    .frame(height: 1)

                // — App voice —
                VStack(spacing: 6) {
                    Text(uiLanguage == .vi ? "Giọng điệu" : "App voice")
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#2D2B26"))

                    // Each chip shows its own explanation inline when selected, so
                    // there's no separate caption below the row. Centered as a group.
                    HStack(spacing: 8) {
                        ForEach(LanguagePersona.allCases, id: \.self) { persona in
                            PersonaChip(
                                persona: persona,
                                isSelected: appState.languagePersona == persona,
                                action: { appState.languagePersona = persona }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            // Light wash + thin (2px) accent pixel border, matching the rest.
            .pixelBox(fill: Color(hex: "#7B6BD8").opacity(0.10),
                      borderColor: Color(hex: "#7B6BD8"),
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
    }
}

// MARK: - Language Style Section

struct LanguageStyleSection: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(uiLanguage == .vi ? "Phong cách ngôn ngữ" : "Language Style")
                .font(.pixelSystem(size: 14, weight: .semibold, design: .default))

            VStack(alignment: .leading, spacing: 10) {
                // Three compact chips in a row…
                HStack(spacing: 8) {
                    ForEach(LanguagePersona.allCases, id: \.self) { persona in
                        PersonaChip(
                            persona: persona,
                            isSelected: appState.languagePersona == persona,
                            action: { appState.languagePersona = persona }
                        )
                    }
                }

                // …and a single caption explaining the active choice, so the
                // per-option blurbs don't each take a full row.
                Text(appState.languagePersona.blurb)
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .pixelBox(fill: Color.white)
        }
    }
}

private struct PersonaChip: View {
    let persona: LanguagePersona
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    private let accent = Color(hex: "#7B6BD8")

    var body: some View {
        Button(action: action) {
            // Bottom-aligned so the name + inline blurb sit on a shared baseline
            // with the icon; centered within the chip.
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(persona.icon)
                    .font(.pixelSystem(size: 15))
                Text(persona.displayName)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? accent : Color(hex: "#2D2B26"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // The active option carries its own explanation, inline — so the
                // selected chip grows to fit while the others stay compact.
                if isSelected {
                    Text(persona.blurb)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? accent.opacity(0.10)
                          : (isHovered ? Color(hex: "#F7F5FC") : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accent : Color(hex: "#E0DBEF"),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Display Language Section

struct DisplayLanguageSection: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(uiLanguage == .vi ? "Ngôn ngữ hiển thị" : "Display Language")
                .font(.pixelSystem(size: 14, weight: .semibold, design: .default))

            VStack(alignment: .leading, spacing: 12) {
                Text(uiLanguage == .vi
                     ? "Đổi ngôn ngữ hiển thị của app. Thay đổi áp dụng ngay lập tức."
                     : "Switch the app's display language. Changes are immediate.")
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: $appState.uiLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text("\(lang.flag)  \(lang.displayName)").tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(16)
            .pixelBox(fill: Color.white)
        }
    }
}

// MARK: - Debug Section

struct DebugSection: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var feedbackManager: FeatureFeedbackManager
    @Environment(\.uiLanguage) private var uiLanguage

    private var helpText: String {
        uiLanguage == .vi
            ? "Thay tab Reflection bằng demo 13 phút có sẵn. ⌥1..⌥4 bắn milestone, ⌥5 hiện reflection, ⌥6..⌥8 health nudge, ⌥9 demo Tips, ⌥0 nhảy thẳng tới summary."
            : "Replaces Reflection tab with hardcoded 13-min demo. ⌥1..⌥4 milestones, ⌥5 reflection, ⌥6..⌥8 health nudge, ⌥9 Tips demo, ⌥0 panic-skip."
    }

    var body: some View {
        // Dev-only — kept to a single slim row. The shortcut blurb lives in a
        // hover tooltip instead of taking a whole paragraph on the profile.
        HStack(spacing: 10) {
            Text(uiLanguage == .vi ? "GỠ LỖI" : "DEBUG")
                .font(.pixelSystem(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.secondary)

            Toggle(isOn: $appState.demoModeEnabled) {
                Text(uiLanguage == .vi ? "Chế độ Demo" : "Demo Mode")
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#2D2B26"))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()

            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .help(helpText)

            // Debug-only feedback testing — compiled OUT of release builds, so the
            // shipped app shows only the real first-experience pop-up.
            #if DEBUG
            Divider().frame(height: 16)

            // Force-show a prompt, or reset the once-ever flags.
            Button(uiLanguage == .vi ? "Thử feedback" : "Test feedback") {
                feedbackManager.debugShow(.exercise)
            }
            .buttonStyle(.link)
            .font(.pixelSystem(size: 10, weight: .medium))
            .help(uiLanguage == .vi
                  ? "Hiện ngay form feedback (gửi thật lên Firestore)."
                  : "Show the feedback pop-up now (submits a real doc to Firestore).")

            Button(uiLanguage == .vi ? "Reset" : "Reset prompts") {
                feedbackManager.debugResetAll()
            }
            .buttonStyle(.link)
            .font(.pixelSystem(size: 10, weight: .medium))
            .help(uiLanguage == .vi
                  ? "Xoá cờ đã-hỏi để các tính năng kích hoạt lại lần sau."
                  : "Clear the 'already asked' flags so features re-trigger.")
            #endif
        }
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Light wash + thin (2px) accent pixel border, matching the rest.
        .pixelBox(fill: Color(hex: "#7B6BD8").opacity(0.10),
                  borderColor: Color(hex: "#7B6BD8"),
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .environmentObject(TourController())
}

// =============================================================================
// MARK: - Streak: compact card + Duolingo-style detail
// =============================================================================

/// Compact streak chip for the Profile bento: flame + day count and a this-week
/// dot strip. Tapping opens the full Duolingo-style detail (`StreakDetailView`).
private struct CompactStreakCard: View {
    let streak: Int
    let snapshots: [DailySnapshot]
    var frozenDays: [Date] = []
    let action: () -> Void

    private let accent = CodepetTheme.accentOrange
    private let darkInk = Color(hex: "#2D2B26")

    private var activeDays: Set<Date> {
        let cal = Calendar.current
        return Set(snapshots.map { cal.startOfDay(for: $0.date) })
    }
    private var frozenSet: Set<Date> {
        let cal = Calendar.current
        return Set(frozenDays.map { cal.startOfDay(for: $0) })
    }

    private struct WeekDay { let label: String; let isActive: Bool; let isToday: Bool; let isFuture: Bool; let isFrozen: Bool }

    /// This week (Sun-start): per-day label + active/today/future/frozen, for the
    /// Duolingo-style weekday strip.
    private var weekDays: [WeekDay] {
        let labels = ["Su", "M", "Tu", "W", "Th", "F", "Sa"]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let active = activeDays
        let frozen = frozenSet
        let weekdayIndex = cal.component(.weekday, from: today) - 1   // 0 = Sun
        guard let sunday = cal.date(byAdding: .day, value: -weekdayIndex, to: today) else {
            return labels.map { WeekDay(label: $0, isActive: false, isToday: false, isFuture: false, isFrozen: false) }
        }
        return (0..<7).map { i in
            let d = cal.startOfDay(for: cal.date(byAdding: .day, value: i, to: sunday) ?? today)
            return WeekDay(label: labels[i],
                           isActive: active.contains(d),
                           isToday: d == today,
                           isFuture: d > today,
                           isFrozen: frozen.contains(d))
        }
    }

    /// Caption mirroring Duolingo's encouragement line.
    private var streakCaption: String {
        let practicedToday = weekDays.contains { $0.isToday && $0.isActive }
        if streak <= 0 { return "Start your streak — practice today!" }
        return practicedToday
            ? "You're on a \(streak)-day streak! Come back tomorrow to make it \(streak + 1)."
            : "You're on a \(streak)-day streak — practice today to keep it alive!"
    }

    /// One day disc: white disc + orange flame for a streak day, otherwise an
    /// empty ring (brighter on today). Matches Duolingo's compact week strip.
    @ViewBuilder
    private func dayDisc(_ day: WeekDay) -> some View {
        ZStack {
            if day.isActive {
                Circle().fill(accent)
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            } else if day.isFrozen {
                Circle().fill(Color(hex: "#4FB0E5"))
                Image(systemName: "snowflake")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle().strokeBorder(darkInk.opacity(day.isToday ? 0.45 : 0.18), lineWidth: 2.5)
            }
        }
        .frame(width: 34, height: 34)
    }

    var body: some View {
        Button(action: action) {
            // Vertical split for the main (70%) card: a TOP row holds the streak
            // summary — count, label, and the encouragement message — and a
            // full-width week calendar sits BELOW a divider.
            // Regular system font throughout (no pixel typeface).
            VStack(alignment: .leading, spacing: 18) {
                // TOP — streak count + label + status message.
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(accent)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(streak)")
                                .font(.system(size: 48, weight: .heavy))
                                .foregroundColor(darkInk)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text("DAY STREAK")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(0.5)
                                .foregroundColor(darkInk.opacity(0.65))
                        }
                        Text(streakCaption)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(darkInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                // Divider between the summary and the calendar.
                Rectangle()
                    .fill(darkInk.opacity(0.12))
                    .frame(height: 1.5)

                // BOTTOM — clean week calendar stretched full width.
                HStack(spacing: 0) {
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 8) {
                            dayDisc(day)
                            Text(day.label)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(darkInk.opacity(day.isToday ? 0.9 : 0.55))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            // Corner accent: open affordance (top-right).
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(darkInk.opacity(0.5))
                    .padding(14)
            }
            // Light "info bar" treatment — a soft orange wash behind a thin (2px)
            // pixel staircase border tinted to the card's own accent (not black).
            .pixelBox(fill: accent.opacity(0.12), borderColor: accent,
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Duolingo-style streak detail, shown as a centered sheet. White canvas, big
/// flame headline, an encouragement banner, month navigation, two stat cards
/// (days practiced / streak freezes), and a month calendar where consecutive
/// active days join into one continuous orange "pill".
private struct StreakDetailView: View {
    let streak: Int
    let best: Int
    let freezes: Int
    let snapshots: [DailySnapshot]
    var frozenDays: [Date] = []

    @Environment(\.dismiss) private var dismiss
    @State private var monthOffset = 0

    private var frozenSet: Set<Date> {
        let cal = Calendar.current
        return Set(frozenDays.map { cal.startOfDay(for: $0) })
    }

    /// Next milestone above the current streak, and the previous rung (for the
    /// progress bar). nil next → all milestones reached.
    private var nextMilestone: StreakMilestone? {
        GameEconomy.streakMilestones.first { $0.day > streak }
    }
    private var prevMilestoneDay: Int {
        GameEconomy.streakMilestones.last { $0.day <= streak }?.day ?? 0
    }

    private let accent = CodepetTheme.accentOrange
    private let darkInk = Color(hex: "#2D2B26")
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

    private var activeDays: Set<Date> {
        let cal = Calendar.current
        return Set(snapshots.map { cal.startOfDay(for: $0.date) })
    }
    private var displayedMonth: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return cal.date(byAdding: .month, value: monthOffset, to: today) ?? today
    }
    private var practicedToday: Bool {
        let cal = Calendar.current
        return activeDays.contains(cal.startOfDay(for: Date()))
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let active = activeDays
        let cells = monthGrid(for: displayedMonth, calendar: cal)
        let monthActive = cells.filter { $0.inMonth && active.contains($0.date) }.count
        let weekRows = stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0 ..< min($0 + 7, cells.count)])
        }

        let frozen = frozenSet

        VStack(alignment: .leading, spacing: 18) {
            header
            banner
            milestoneSection
            monthNav
            statRow(daysPracticed: monthActive)
            weekdayHeader
            VStack(spacing: 4) {
                ForEach(weekRows.indices, id: \.self) { r in
                    weekRow(weekRows[r], today: today, active: active, frozen: frozen)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color.white)
        .overlay(alignment: .topTrailing) { closeButton.padding(14) }
    }

    /// Next-milestone goal + a row of earned milestone badges.
    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let next = nextMilestone {
                let span = max(1, next.day - prevMilestoneDay)
                let done = min(span, streak - prevMilestoneDay)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(next.day - streak) day\(next.day - streak == 1 ? "" : "s") to your \(next.day)-day reward")
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(darkInk.opacity(0.7))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(accent.opacity(0.15)).frame(height: 8)
                            Capsule().fill(accent)
                                .frame(width: geo.size.width * CGFloat(done) / CGFloat(span), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            } else {
                Text("🏆 You've reached every streak milestone!")
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(darkInk.opacity(0.7))
            }

            // Earned milestone badges
            HStack(spacing: 8) {
                ForEach(GameEconomy.streakMilestones, id: \.day) { m in
                    let earned = streak >= m.day
                    HStack(spacing: 3) {
                        Image(systemName: earned ? "flame.fill" : "flame")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(earned ? accent : darkInk.opacity(0.25))
                        Text("\(m.day)")
                            .font(.pixelSystem(size: 11, weight: .bold))
                            .foregroundColor(earned ? darkInk : darkInk.opacity(0.3))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(earned ? accent.opacity(0.12) : Color(hex: "#F4F2F8")))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(accent)
                Text("day streak")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(accent)
                if best > 0 {
                    Text("Longest: \(best) day\(best == 1 ? "" : "s")")
                        .font(.pixelSystem(size: 11, weight: .medium))
                        .foregroundColor(darkInk.opacity(0.5))
                }
            }
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 56))
                .foregroundColor(accent)
                .shadow(color: accent.opacity(0.3), radius: 8, y: 3)
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 18))
                .foregroundColor(accent)
            Text(practicedToday
                 ? "You practiced today — keep the flame alive!"
                 : "Keep your streak — code or finish a lesson today!")
                .font(.pixelSystem(size: 13, weight: .medium))
                .foregroundColor(darkInk.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.12)))
    }

    private var monthNav: some View {
        HStack {
            Text(Self.monthFormatter.string(from: displayedMonth))
                .font(.pixelSystem(size: 17, weight: .bold))
                .foregroundColor(darkInk)
            Spacer()
            navButton("chevron.left", enabled: monthOffset > -11) { if monthOffset > -11 { monthOffset -= 1 } }
            navButton("chevron.right", enabled: monthOffset < 0) { if monthOffset < 0 { monthOffset += 1 } }
        }
    }

    private func statRow(daysPracticed: Int) -> some View {
        HStack(spacing: 12) {
            statCard(icon: "checkmark.circle.fill", tint: accent,
                     value: "\(daysPracticed)", label: "Days practiced")
            statCard(icon: "snowflake", tint: Color(hex: "#4FB0E5"),
                     value: "\(freezes)", label: "Streak freezes")
        }
    }

    private func statCard(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 18, weight: .heavy)).foregroundColor(darkInk)
                Text(label).font(.pixelSystem(size: 10)).foregroundColor(darkInk.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#F4F2F8")))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdaySymbols[i])
                    .font(.pixelSystem(size: 12, weight: .bold))
                    .foregroundColor(darkInk.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// One week as a row of 7 equal cells (spacing 0) so consecutive active-day
    /// pills abut into a single continuous capsule.
    private func weekRow(_ row: [DayCell], today: Date, active: Set<Date>, frozen: Set<Date>) -> some View {
        // Frozen days bridge the streak, so they connect the pill too.
        let flags = row.map { ($0.inMonth && active.contains($0.date)) || frozen.contains($0.date) }
        return HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.element.id) { col, cell in
                dayCell(cell,
                        isActive: flags[col],
                        isFrozen: frozen.contains(cell.date),
                        leftRound: !(col > 0 && flags[col - 1]),
                        rightRound: !(col < row.count - 1 && flags[col + 1]),
                        isToday: cell.date == today)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCell, isActive: Bool, isFrozen: Bool, leftRound: Bool,
                         rightRound: Bool, isToday: Bool) -> some View {
        let dayNum = Calendar.current.component(.day, from: cell.date)
        let r: CGFloat = 17
        ZStack {
            if isActive {
                UnevenRoundedRectangle(
                    topLeadingRadius: leftRound ? r : 0,
                    bottomLeadingRadius: leftRound ? r : 0,
                    bottomTrailingRadius: rightRound ? r : 0,
                    topTrailingRadius: rightRound ? r : 0
                )
                .fill(accent)
                .frame(height: 34)
            }
            if isToday {
                Circle()
                    .strokeBorder(isActive ? Color.white.opacity(0.9) : accent, lineWidth: 2)
                    .frame(width: 34, height: 34)
            }
            if isFrozen {
                // A freeze covered this day — show a snowflake on the pill.
                Image(systemName: "snowflake")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(dayNum)")
                    .font(.pixelSystem(size: 14, weight: isToday ? .heavy : .semibold))
                    .foregroundColor(numberColor(isActive: isActive, isToday: isToday, inMonth: cell.inMonth))
            }
        }
        .frame(height: 38)
    }

    private func numberColor(isActive: Bool, isToday: Bool, inMonth: Bool) -> Color {
        if isActive { return .white }
        if !inMonth { return darkInk.opacity(0.25) }
        if isToday { return accent }
        return darkInk
    }

    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(darkInk.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(hex: "#F0F0EC")))
        }
        .buttonStyle(.plain)
    }

    private func navButton(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? darkInk : darkInk.opacity(0.25))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#F4F2F8")))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: grid
    private struct DayCell: Identifiable {
        let id = UUID()
        let date: Date
        let inMonth: Bool
    }

    private func monthGrid(for monthDate: Date, calendar cal: Calendar) -> [DayCell] {
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }
        let daysInMonth = range.count
        let leading = cal.component(.weekday, from: firstOfMonth) - 1
        let total = leading + daysInMonth
        let weeks = Int(ceil(Double(total) / 7.0))
        let gridStart = cal.date(byAdding: .day, value: -leading, to: firstOfMonth)!
        return (0..<(weeks * 7)).map { i in
            let date = cal.date(byAdding: .day, value: i, to: gridStart)!
            let inMonth = cal.isDate(date, equalTo: firstOfMonth, toGranularity: .month)
            return DayCell(date: cal.startOfDay(for: date), inMonth: inMonth)
        }
    }
}
