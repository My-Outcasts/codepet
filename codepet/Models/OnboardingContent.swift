// codepet/Models/OnboardingContent.swift
import SwiftUI

/// Ported constants for the first-run cinematic onboarding (verbatim from the web
/// app's lib/data.ts + Onboarding.tsx). English-only by design.
enum OnboardingContent {
    /// Per-step colour grade laid over the art panel (web STEP_GRADE), applied soft-light.
    /// One hue per scene, steps 0...8. Alpha baked in (0.22–0.28) to match web.
    static let stepGrade: [Color] = [
        Color(red: 124/255, green: 58/255,  blue: 237/255).opacity(0.28), // 0
        Color(red: 255/255, green: 157/255, blue: 107/255).opacity(0.24), // 1
        Color(red: 110/255, green: 168/255, blue: 255/255).opacity(0.24), // 2
        Color(red: 79/255,  green: 224/255, blue: 207/255).opacity(0.24), // 3
        Color(red: 208/255, green: 140/255, blue: 245/255).opacity(0.26), // 4
        Color(red: 242/255, green: 201/255, blue: 76/255 ).opacity(0.22), // 5
        Color(red: 126/255, green: 168/255, blue: 255/255).opacity(0.26), // 6
        Color(red: 124/255, green: 58/255,  blue: 237/255).opacity(0.26), // 7
        Color(red: 124/255, green: 58/255,  blue: 237/255).opacity(0.26), // 8
    ]

    /// (display label, stable key) — the numbered single-select on the role step.
    static let roles: [(label: String, key: String)] = [
        ("Founder building a product", "founder"),
        ("Engineer / developer", "eng"),
        ("Designer who codes", "design"),
        ("Product manager", "product"),
        ("Marketing / growth", "mkt"),
        ("Operations / business", "ops"),
        ("Solo / indie hacker", "solo"),
        ("Something else", "other"),
    ]
    /// (display label, stable key) — how hands-on with the code.
    static let tech: [(label: String, key: String)] = [
        ("I write the code myself", "hands"),
        ("I direct engineers / build with AI", "direct"),
        ("I'm not on the technical side", "non"),
    ]
    static let stages = [
        "Just an idea", "Prototype", "Private beta", "Public beta", "Launched", "Growing",
    ]
    static let stageNotes = [
        "Perfect — I'll focus on shaping the idea and pressure-testing it.",
        "Great — let's turn the prototype into something testable.",
        "I'll help you run a tight private beta and learn fast.",
        "I'll focus on measurement, polish, and getting to launch.",
        "I'll help you grow distribution and tighten the funnel.",
        "I'll focus on scaling what already works.",
    ]
    static let categories = [
        "Web app", "Mobile app", "SaaS", "Dev tool", "AI / ML", "Marketplace", "Game", "Other",
    ]
    /// (name, dot color) — cold-open department preview chips (DEPTS + DEPT_DOT).
    static let departments: [(name: String, dot: Color)] = [
        ("Engineering", Color(hex: "#6ea8ff")),
        ("Marketing", Color(hex: "#ff9d6b")),
        ("Operations", Color(hex: "#4fe0cf")),
        ("Finance", Color(hex: "#f2c94c")),
        ("Legal", Color(hex: "#b98cf0")),
        ("Design", Color(hex: "#d08cf5")),
        ("Sales", Color(hex: "#7ea8ff")),
        ("Support", Color(hex: "#7fd694")),
    ]
    /// Per-step left-panel art (STEP_ART), steps 0...8. Steps 0, 7 & 8 reuse ob-team.
    static let stepArt = [
        "ob-team", "ob-couch", "ob-chess", "ob-drummer",
        "ob-observatory", "ob-isometric", "ob-boardroom", "ob-team",
    ]
    static let analysisLines = [
        "Reading what you told me…",
        "Mapping it across 8 departments",
        "Cross-checking your space & stage",
        "Drafting your roadmap to launch",
    ]
    /// Total onboarding screens INCLUDING the cinematic cold-open (step 0). The footer
    /// counts `step + 1` of `total` — matching the web (`OB_TOTAL`), where the cold-open
    /// is counted but renders no footer, so the first question reads "Step 2 of 9".
    static let total = 8
    static let defaultStageIndex = 2

    /// Web CSS theme vars, mapped 1:1. `surface2`/`well`/`faint` alias the shared
    /// `CodepetTokens` values directly — they used to be re-declared here with their
    /// own hex literals under a comment claiming `CodepetTheme` didn't already expose
    /// them, which was false: it did, and the duplication meant a retint of one and not
    /// the other would have split the palette silently. The accent trio below IS still
    /// duplicated; it is out of scope for the surface retint and left as-is
    /// deliberately. `coldBg` is a genuine one-off (cold-open / splash, stays dark) and
    /// is correct as-is.
    enum Palette {
        static let surface2   = CodepetTokens.surface2
        static let well       = CodepetTokens.well
        static let faint      = CodepetTokens.faint
        static let accentDeep = Color.dyn("#5b27b0", "#7c3aed")   // --accent-deep
        static let accentTint = Color.dyn("#eee6fd", "#271f3a")   // --accent-tint
        static let accentLine = Color.dyn("#d9c9f7", "#43356b")   // --accent-line
        static let coldBg     = Color(hex: "#100a26")             // cold-open / splash — STAYS dark
    }
}
