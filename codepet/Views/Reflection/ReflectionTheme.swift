import SwiftUI

// MARK: - Design tokens

enum ReflectionTheme {

    // MARK: - Brand palette
    // Canonical Codepet brand colors — use these for high-impact accents,
    // badges, and interactive elements. Keep surfaces/backgrounds soft.
    static let brandPurple = Color(red: 0x95 / 255.0, green: 0x38 / 255.0, blue: 0xCF / 255.0) // #9538CF
    static let brandOrange = Color(red: 0xF5 / 255.0, green: 0x83 / 255.0, blue: 0x45 / 255.0) // #F58345
    static let brandYellow = Color(red: 0xFC / 255.0, green: 0xBE / 255.0, blue: 0x1D / 255.0) // #FCBE1D
    static let brandGreen  = Color(red: 0x02 / 255.0, green: 0x99 / 255.0, blue: 0x02 / 255.0) // #029902
    static let brandBlue   = Color(red: 0x1C / 255.0, green: 0x40 / 255.0, blue: 0xCF / 255.0) // #1C40CF
    static let brandPink   = Color(red: 0xFF / 255.0, green: 0x8C / 255.0, blue: 0xC9 / 255.0) // #FF8CC9
    static let brandRed    = Color(red: 0xE2 / 255.0, green: 0x4B / 255.0, blue: 0x4A / 255.0) // #E24B4A

    // Accent — primary interactive color for the Reflection tab.
    // Defaults to brand purple but is retinted to the ACTIVE CHARACTER's color
    // at runtime (set from MainTabView) so the whole tab — sidebar wash, project
    // headers, welcome card, thread lines — stays cohesive with your pet.
    // Semantic colors below (mood, source tints) intentionally do NOT follow it.
    static var accent: Color = brandPurple

    // Mood — mapped to brand colors for vibrancy
    static let moodCalm = brandGreen
    static let moodEngaged = brandBlue
    static let moodAlert = brandOrange

    static func color(for mood: PetMood) -> Color {
        switch mood {
        case .calm: return moodCalm
        case .engaged: return moodEngaged
        case .alert: return moodAlert
        }
    }

    // Narrative-mood → brand-color bubble fills (distinct wash per mood)
    // Content readability is king — fills stay very subtle (0.05–0.08) so
    // dark text (#2D2B26) and markdown links always pop against the background.
    // The mood color shows through the left-border strip and title badge instead.
    static func bubbleFill(for mood: NarrativeMood) -> Color {
        switch mood {
        case .excited:   return brandOrange.opacity(0.06)
        case .thinking:  return brandBlue.opacity(0.05)
        case .proud:     return brandGreen.opacity(0.05)
        case .concerned: return brandPink.opacity(0.06)
        case .cheering:  return brandYellow.opacity(0.08)
        case .idle:      return bubbleWarmStart
        }
    }

    // Narrative-mood → accent for left-border strips, thread lines, badge tints
    static func moodAccentColor(for mood: NarrativeMood) -> Color {
        switch mood {
        case .excited:   return brandOrange
        case .thinking:  return brandBlue
        case .proud:     return brandGreen
        case .concerned: return brandPink
        case .cheering:  return brandYellow
        case .idle:      return brandPurple
        }
    }

    // Source tints — derived from brand palette
    static let cursorTintBg = brandPurple.opacity(0.10)
    static let cursorTintFg = brandPurple
    static let claudeTintBg = brandGreen.opacity(0.12)
    static let claudeTintFg = brandGreen
    static let codexTintBg  = brandOrange.opacity(0.12)
    static let codexTintFg  = brandOrange
    static let manualTintBg = Color(red: 0x2D / 255.0, green: 0x2B / 255.0, blue: 0x26 / 255.0).opacity(0.06)
    static let manualTintFg = Color(red: 0x66 / 255.0, green: 0x66 / 255.0, blue: 0x66 / 255.0)

    static func sourceTintBg(for source: EventSource) -> Color {
        switch source {
        case .cursorChat: return cursorTintBg
        case .claudeCode: return claudeTintBg
        case .codex:      return codexTintBg
        case .manualLog:  return manualTintBg
        }
    }

    static func sourceTintFg(for source: EventSource) -> Color {
        switch source {
        case .cursorChat: return cursorTintFg
        case .claudeCode: return claudeTintFg
        case .codex:      return codexTintFg
        case .manualLog:  return manualTintFg
        }
    }

    // Text
    static let primaryText = Color(red: 0x2D / 255.0, green: 0x2B / 255.0, blue: 0x26 / 255.0)
    static let secondaryText = Color(red: 0x4F / 255.0, green: 0x4B / 255.0, blue: 0x45 / 255.0)
    static let mutedText = Color(red: 0x94 / 255.0, green: 0x8E / 255.0, blue: 0x82 / 255.0)

    // Surfaces
    static let background = Color(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xF6 / 255.0)
    static let cardBackground = Color.white
    static let borderLight = Color(red: 0xEB / 255.0, green: 0xE8 / 255.0, blue: 0xDF / 255.0)

    // Sidebar — light wash of the active accent (follows the character color)
    static var sidebarTop: Color { accent.opacity(0.06) }
    static var sidebarBottom: Color { accent.opacity(0.02) }
    static var sidebarBorder: Color { accent.opacity(0.10) }

    // Narrative bubble fills — warm (orange-tinted) and cool (purple-tinted)
    static let bubbleWarmStart = Color(red: 0xFF / 255.0, green: 0xF5 / 255.0, blue: 0xE8 / 255.0) // warm orange wash
    static let bubbleWarmEnd = Color(red: 0xFF / 255.0, green: 0xEE / 255.0, blue: 0xD4 / 255.0)
    static let bubblePurpleStart = brandPurple.opacity(0.06) // cool purple wash
    static let bubblePurpleEnd = brandPurple.opacity(0.04)

    // Session recap bubble — light wash of the active accent (follows the pet color)
    static var bubbleAccentWash: Color { accent.opacity(0.06) }

    // Thread line — follows the active accent gradient
    static var threadLineTop: Color { accent.opacity(0.30) }
    static var threadLineBottom: Color { accent.opacity(0.06) }

    // Session strip — follows the active accent so the recap meta row stays
    // cohesive with the selected character's color.
    static var stripBackground: Color { accent.opacity(0.10) }
    static var stripText: Color { accent }

    // Reminder card — red for urgency/attention
    static let reminderBackground = brandRed.opacity(0.08)
    static let reminderBorder = brandRed
    static let reminderText = brandRed

    // Lesson card — brand yellow/orange
    static let lessonFill = Color(red: 0xFC / 255.0, green: 0xEB / 255.0, blue: 0xA8 / 255.0) // warm yellow
    static let lessonIconColor = brandOrange
    static let lessonTextColor = Color(red: 0x85 / 255.0, green: 0x4F / 255.0, blue: 0x0B / 255.0)

    // Next steps card — brand blue
    static let nextStepsFill = Color(red: 0xD6 / 255.0, green: 0xEA / 255.0, blue: 0xF8 / 255.0)
    static let nextStepsIconColor = brandBlue
    static let nextStepsTextColor = Color(red: 0x0C / 255.0, green: 0x44 / 255.0, blue: 0x7C / 255.0)

    // Live badge
    static let liveBadge = brandGreen

    // Fonts — Reflection lives in the body/content tier, so all three helpers
    // resolve to Inter. Use `CodepetTheme.display()` for true display text.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return CodepetTheme.inter(size, weight: weight)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return CodepetTheme.inter(size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // True monospace (SF Mono) so commands, paths, and JSON align column-wise
        // and read as code — not the proportional Inter the other helpers use.
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - PetAvatar

struct PetAvatar: View {
    @EnvironmentObject var appState: AppState

    let mood: PetMood
    let size: CGFloat

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Circle container with pet color fill
            Circle()
                .fill(character.color.opacity(0.14))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(character.color.opacity(0.35), lineWidth: max(size * 0.035, 1.5))
                )
                .overlay(
                    // Header avatar: breathing only (no charIdle — its -6px offset
                    // and ±2° rotation are too aggressive for this small context).
                    // compositingGroup() flattens the scaleEffect from petBreathing
                    // into the render buffer so clipShape reliably clips it.
                    CharacterImage(character.id, size: size * 0.75)
                        .petBreathing()
                        .frame(width: size, height: size)
                        .compositingGroup()
                        .clipShape(Circle())
                )

            // Mood indicator dot
            Circle()
                .fill(ReflectionTheme.color(for: mood))
                .overlay(Circle().stroke(Color.white, lineWidth: max(size * 0.04, 1.5)))
                .frame(width: size * 0.26, height: size * 0.26)
                .offset(x: size * 0.04, y: size * 0.04)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - TriggerPill

struct TriggerPill: View {
    let trigger: TriggerTag

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ReflectionTheme.accent)
                .frame(width: 5, height: 5)
            Text("\(trigger.code) · \(trigger.label)")
                .font(ReflectionTheme.sans(11, weight: .medium))
                .foregroundColor(ReflectionTheme.accent)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(ReflectionTheme.accent.opacity(0.10))
        )
    }
}

// MARK: - Eyebrow

struct Eyebrow: View {
    let text: String
    var color: Color = ReflectionTheme.mutedText

    var body: some View {
        Text(text.uppercased())
            .font(ReflectionTheme.sans(10, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(color)
    }
}

// MARK: - Section title

/// A top-level section header that matches the Profile tab's "Your progress"
/// title: larger and darker than an Eyebrow (13pt, subtle tracking). Use for
/// primary section labels; use Eyebrow for the smaller secondary labels.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(hex: "#2D2B26").opacity(0.65))
            .tracking(0.5)
            .textCase(.uppercase)
    }
}

// MARK: - Source label pill

struct SourceEyebrow: View {
    let source: EventSource

    var body: some View {
        Text(source.rawValue.uppercased())
            .font(ReflectionTheme.sans(9, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(ReflectionTheme.sourceTintFg(for: source))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(ReflectionTheme.sourceTintBg(for: source))
            )
    }
}
