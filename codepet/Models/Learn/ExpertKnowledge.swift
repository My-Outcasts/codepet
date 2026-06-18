import Foundation

// =============================================================================
// MARK: - Expert Knowledge Schema
// =============================================================================

/// A single piece of practical knowledge from an expert.
/// The matching engine selects relevant entries based on the user's project
/// context (tech stack, recent activity, health gaps) and injects them into
/// the AI prompt so the pet can give grounded, expert-informed advice.
struct KnowledgeEntry: Identifiable, Codable, Equatable {
    let id: String

    /// Which expert this knowledge comes from.
    let expertId: String

    /// Short name for internal reference (not shown to users).
    let label: String

    /// The type of knowledge — determines how the matching engine uses it.
    let kind: KnowledgeKind

    /// Technologies this entry applies to. Empty = universal.
    /// e.g. ["SwiftUI", "Firebase", "CSS", "HTML", "React"]
    let techTags: [String]

    /// Conditions that make this entry relevant. The matcher checks these
    /// against the user's project context. If ANY trigger matches, the
    /// entry is a candidate.
    let triggers: [KnowledgeTrigger]

    /// The expert's actual advice, written in their voice.
    /// This gets injected into the AI prompt as context.
    let advice: String

    /// One-line version for quick display in the UI (e.g. guidance card).
    let oneLiner: String

    /// Optional reference back to a case study chapter where this
    /// knowledge is explained in depth.
    let caseStudyChapterId: String?
}

// MARK: - Knowledge kinds

/// What type of knowledge this entry represents.
enum KnowledgeKind: String, Codable, Equatable {
    /// A universal principle that applies broadly.
    /// e.g. "Ship core loop before polish"
    case principle

    /// A situational response triggered by a specific pattern.
    /// e.g. "If no tests exist, warn about launch-day bugs"
    case patternResponse

    /// A technical insight tied to a specific tool or framework.
    /// e.g. "Use .interpolation(.none) for pixel art in SwiftUI"
    case codeWisdom

    /// A mindset or motivation insight.
    /// e.g. "Deadlines with witnesses actually work"
    case mindset
}

// MARK: - Trigger conditions

/// A condition that makes a knowledge entry relevant to the current context.
enum KnowledgeTrigger: Codable, Equatable {
    /// User's project uses this technology.
    /// e.g. .usesTech("SwiftUI")
    case usesTech(String)

    /// A health check is failing for this item.
    /// e.g. .healthGapExists("tests") — user has no test files
    case healthGapExists(String)

    /// User has been working on a specific type of activity recently.
    /// e.g. .recentActivity("ui-building") — lots of view file edits
    case recentActivity(String)

    /// User hasn't done something in a while.
    /// e.g. .inactiveArea("styling") — no CSS/styling work
    case inactiveArea(String)

    /// Project is at a certain stage.
    /// e.g. .projectStage("pre-launch") — not yet submitted to App Store
    case projectStage(String)

    /// Always relevant — universal advice.
    case always
}

// MARK: - Knowledge Matcher

/// Selects the most relevant knowledge entries for a given project context.
enum KnowledgeMatcher {

    /// Project context provided by the app at guidance/narrative time.
    struct ProjectContext {
        let techStack: [String]          // e.g. ["SwiftUI", "Firebase"]
        let healthGaps: [String]         // e.g. ["tests", "ci", "readme"]
        let recentActivities: [String]   // e.g. ["ui-building", "auth-setup"]
        let inactiveAreas: [String]      // e.g. ["styling", "testing"]
        let projectStage: String         // e.g. "building", "pre-launch", "launched"
    }

    /// Returns the top-N most relevant entries for the given context.
    /// Entries are scored by how many triggers match.
    static func match(
        entries: [KnowledgeEntry],
        context: ProjectContext,
        limit: Int = 5
    ) -> [KnowledgeEntry] {
        let scored = entries.map { entry -> (KnowledgeEntry, Int) in
            let score = entry.triggers.reduce(0) { acc, trigger in
                acc + (triggerMatches(trigger, context: context) ? 1 : 0)
            }
            // Bonus point if tech tags overlap with project tech stack
            let techBonus = entry.techTags.isEmpty ? 0 :
                entry.techTags.filter { context.techStack.contains($0) }.isEmpty ? 0 : 1
            return (entry, score + techBonus)
        }

        return scored
            .filter { $0.1 > 0 }  // must have at least one match
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    private static func triggerMatches(
        _ trigger: KnowledgeTrigger,
        context: ProjectContext
    ) -> Bool {
        switch trigger {
        case .usesTech(let tech):
            return context.techStack.contains(tech)
        case .healthGapExists(let gap):
            return context.healthGaps.contains(gap)
        case .recentActivity(let activity):
            return context.recentActivities.contains(activity)
        case .inactiveArea(let area):
            return context.inactiveAreas.contains(area)
        case .projectStage(let stage):
            return context.projectStage == stage
        case .always:
            return true
        }
    }
}

// =============================================================================
// MARK: - Astro's Knowledge Entries
// =============================================================================

/// Astro Tran's practical knowledge, extracted from case studies and
/// real experience building shipped products.
enum AstroKnowledge {

    static let entries: [KnowledgeEntry] = [

        // =====================================================================
        // Principles (universal)
        // =====================================================================

        KnowledgeEntry(
            id: "ak_ship_over_perfect",
            expertId: "expert_astro",
            label: "Ship > Perfect",
            kind: .principle,
            techTags: [],
            triggers: [.always, .projectStage("building")],
            advice: "A shipped app with 8 features beats an unshipped app with 47. When I built Codepet, I cut 39 features to ship in a week. Every cut hurt, but an unshipped app helps exactly zero people. Focus your standards on fewer things so each one actually works.",
            oneLiner: "Ship 8 polished features, not 47 half-built ones.",
            caseStudyChapterId: "cs_codepet_mvp_ch1"
        ),

        KnowledgeEntry(
            id: "ak_core_loop_first",
            expertId: "expert_astro",
            label: "Core loop before polish",
            kind: .principle,
            techTags: [],
            triggers: [.always, .recentActivity("ui-building")],
            advice: "Build the core loop with ugly placeholders first. When I built Codepet, I had gray rectangles and system fonts for 12 hours before adding any design. But I could play through the whole flow: pick a character, answer questions, earn coins. If the loop doesn't feel good without polish, no amount of animation will save it. But if it does feel good? Every hour on visuals amplifies something that already works.",
            oneLiner: "If it feels good with gray rectangles, polish will make it great.",
            caseStudyChapterId: "cs_codepet_mvp_ch2"
        ),

        KnowledgeEntry(
            id: "ak_boring_tools",
            expertId: "expert_astro",
            label: "Pick boring tools",
            kind: .principle,
            techTags: [],
            triggers: [.always, .projectStage("building")],
            advice: "Pick the tool you know, not the tool that's trendy. I set up Firebase in 2 hours because I'd used it before. I could have spent a week evaluating newer platforms. Speed of execution beats technical novelty in an MVP. Save the experiments for v2.",
            oneLiner: "Use the tool you know. Speed beats novelty in an MVP.",
            caseStudyChapterId: "cs_codepet_mvp_ch4"
        ),

        KnowledgeEntry(
            id: "ak_constraints_superpower",
            expertId: "expert_astro",
            label: "Constraints are superpowers",
            kind: .principle,
            techTags: [],
            triggers: [.always],
            advice: "Constraints force clarity. When I had to make 8 characters with no art skills, I gave myself a rule: 16×16 pixels, 4 colors, no exceptions. The constraint eliminated overthinking. Byte took 20 minutes. All 8 characters were done in an afternoon. If you're stuck, add a constraint — it sounds backwards, but it works.",
            oneLiner: "Add a constraint to eliminate overthinking.",
            caseStudyChapterId: "cs_codepet_mvp_ch3"
        ),

        KnowledgeEntry(
            id: "ak_first_submit_fails",
            expertId: "expert_astro",
            label: "First submission will fail",
            kind: .principle,
            techTags: [],
            triggers: [.projectStage("pre-launch")],
            advice: "Your first upload will fail. Something will be wrong with signing, entitlements, or metadata. When I submitted Codepet, I got 'Invalid Binary' at 10:47 PM on launch day. The fix took 4 minutes but finding it took an hour. Build in buffer time for at least two failed uploads. Ship it anyway — ship it at 11 PM, ship it nervous, ship it imperfect.",
            oneLiner: "Budget for two failed uploads. Ship it anyway.",
            caseStudyChapterId: "cs_codepet_mvp_ch5"
        ),

        // =====================================================================
        // Pattern Responses (triggered by user's project state)
        // =====================================================================

        KnowledgeEntry(
            id: "ak_no_tests_warning",
            expertId: "expert_astro",
            label: "No tests = launch risk",
            kind: .patternResponse,
            techTags: [],
            triggers: [.healthGapExists("tests")],
            advice: "I see you don't have tests yet. Let me tell you about the 5 bugs that almost killed my launch — every single one would've been caught by a basic test. You don't need 100% coverage. Write tests for the 3 things that would be catastrophic if they broke: auth flow, data persistence, and the core user journey.",
            oneLiner: "No tests? Write 3 tests for your 3 most catastrophic failure points.",
            caseStudyChapterId: nil
        ),

        KnowledgeEntry(
            id: "ak_too_many_features",
            expertId: "expert_astro",
            label: "Feature bloat warning",
            kind: .patternResponse,
            techTags: [],
            triggers: [.recentActivity("adding-features"), .projectStage("building")],
            advice: "You've been adding a lot of new stuff recently. Pause and ask: can a user complete the core experience without what you're building right now? When I built Codepet, I had to kill 39 features I loved. The app shipped because of what I removed, not what I added.",
            oneLiner: "Pause. Can the core experience work without this feature?",
            caseStudyChapterId: "cs_codepet_mvp_ch1"
        ),

        KnowledgeEntry(
            id: "ak_polish_before_loop",
            expertId: "expert_astro",
            label: "Polishing too early",
            kind: .patternResponse,
            techTags: [],
            triggers: [.recentActivity("styling"), .inactiveArea("core-logic")],
            advice: "I notice you've been spending time on styling but your core flow might not be solid yet. When I built Codepet, I forced myself to have gray rectangles for 12 hours before adding any design. The rule: make it work, then make it pretty. If you polish first and the core loop doesn't feel right, you'll have to redo the polish anyway.",
            oneLiner: "Make it work first, then make it pretty.",
            caseStudyChapterId: "cs_codepet_mvp_ch2"
        ),

        KnowledgeEntry(
            id: "ak_no_backend_yet",
            expertId: "expert_astro",
            label: "No cloud sync nudge",
            kind: .patternResponse,
            techTags: [],
            triggers: [.healthGapExists("backend"), .projectStage("building")],
            advice: "Your app doesn't have cloud sync yet. That's fine for now — I built Codepet with just UserDefaults for the first 5 days. But before you ship, users will expect their progress to survive an app deletion. Firebase took me 2 hours to set up. The key: start with anonymous auth so users can use the app immediately, then let them link a real account later.",
            oneLiner: "UserDefaults is fine for now. Add Firebase before shipping.",
            caseStudyChapterId: "cs_codepet_mvp_ch4"
        ),

        KnowledgeEntry(
            id: "ak_deadline_missing",
            expertId: "expert_astro",
            label: "No deadline set",
            kind: .patternResponse,
            techTags: [],
            triggers: [.projectStage("building"), .inactiveArea("shipping")],
            advice: "You've been building for a while without a ship date. When I built Codepet, I gave myself exactly 7 days and told people about it. Deadlines with witnesses actually work — the social pressure turns 'I should ship eventually' into 'I have to ship by Sunday.' Set a date. Tell someone.",
            oneLiner: "Set a ship date and tell someone. Deadlines with witnesses work.",
            caseStudyChapterId: "cs_codepet_mvp_ch5"
        ),

        // =====================================================================
        // Code Wisdom (tech-specific)
        // =====================================================================

        KnowledgeEntry(
            id: "ak_swiftui_state",
            expertId: "expert_astro",
            label: "SwiftUI state architecture",
            kind: .codeWisdom,
            techTags: ["SwiftUI"],
            triggers: [.usesTech("SwiftUI"), .recentActivity("state-management")],
            advice: "Use a single AppState ObservableObject as your source of truth and inject it via .environmentObject(). Don't pass data through 5 levels of initializers. When I built Codepet, one AppState class held everything — completed lessons, coins, character selection — and every view just read from it. Two lines to update state, and SwiftUI re-renders automatically.",
            oneLiner: "One AppState, one source of truth, zero prop drilling.",
            caseStudyChapterId: "cs_codepet_mvp_ch2"
        ),

        KnowledgeEntry(
            id: "ak_pixel_art_rendering",
            expertId: "expert_astro",
            label: "Pixel art rendering",
            kind: .codeWisdom,
            techTags: ["SwiftUI"],
            triggers: [.usesTech("SwiftUI"), .recentActivity("pixel-art")],
            advice: "Pixel art looks terrible if your framework applies bilinear interpolation. In SwiftUI, add .interpolation(.none) to every Image view that displays pixel art. This forces nearest-neighbor scaling which keeps every pixel crisp at any size. I added this to every sprite in Codepet and it was the difference between blurry blobs and clean characters.",
            oneLiner: "Always use .interpolation(.none) for pixel art in SwiftUI.",
            caseStudyChapterId: "cs_codepet_mvp_ch3"
        ),

        KnowledgeEntry(
            id: "ak_firebase_anon_auth",
            expertId: "expert_astro",
            label: "Firebase anonymous auth",
            kind: .codeWisdom,
            techTags: ["Firebase"],
            triggers: [.usesTech("Firebase"), .recentActivity("auth-setup")],
            advice: "Start with anonymous auth. Users can use your app immediately — no sign-up screen, no email required, zero friction. They get a real Firebase UID so you can save their progress to Firestore. Later, they can link an email or Google account to keep their data. This single decision doubled Codepet's onboarding completion rate compared to requiring email first.",
            oneLiner: "Anonymous auth first, real accounts later. Zero friction onboarding.",
            caseStudyChapterId: "cs_codepet_mvp_ch4"
        ),

        KnowledgeEntry(
            id: "ak_firestore_simple_schema",
            expertId: "expert_astro",
            label: "Keep Firestore simple",
            kind: .codeWisdom,
            techTags: ["Firebase"],
            triggers: [.usesTech("Firebase")],
            advice: "For your MVP, use one Firestore collection called 'users' where each document is keyed by UID. Write the full app state as a flat dictionary. No complex schema, no subcollections, no joins. My entire Codepet sync service was 80 lines of Swift. You can add structure later when you actually need it — premature schema design is just premature optimization by another name.",
            oneLiner: "One collection, flat documents, 80 lines. Add complexity when you need it.",
            caseStudyChapterId: "cs_codepet_mvp_ch4"
        ),

        KnowledgeEntry(
            id: "ak_html_structure_first",
            expertId: "expert_astro",
            label: "HTML structure before CSS",
            kind: .codeWisdom,
            techTags: ["HTML", "CSS"],
            triggers: [.usesTech("HTML"), .inactiveArea("styling")],
            advice: "Build all your HTML structure before touching CSS. Get every section, form, card, and layout in place with plain semantic HTML. This is exactly what I did with Codepet's SwiftUI views — gray rectangles first, styling after. The same principle applies to web: if your content structure is wrong, no amount of CSS will fix the layout. But if the structure is right, styling is just decoration.",
            oneLiner: "Semantic HTML first, CSS is decoration. Structure before style.",
            caseStudyChapterId: "cs_codepet_mvp_ch2"
        ),

        // =====================================================================
        // Mindset (motivation and mental models)
        // =====================================================================

        KnowledgeEntry(
            id: "ak_it_never_feels_ready",
            expertId: "expert_astro",
            label: "It never feels ready",
            kind: .mindset,
            techTags: [],
            triggers: [.projectStage("pre-launch"), .always],
            advice: "The difference between people who have shipped an app and people who haven't is usually just the willingness to hit submit when it doesn't feel ready. It will never feel ready. I submitted Codepet at 11 PM on a Sunday night with a list of 20 things I wanted to fix. The app got approved. Users loved it. Those 20 things? Half of them didn't matter.",
            oneLiner: "It will never feel ready. Ship it anyway.",
            caseStudyChapterId: "cs_codepet_mvp_ch5"
        ),

        KnowledgeEntry(
            id: "ak_cutting_is_not_lowering",
            expertId: "expert_astro",
            label: "Cutting isn't lowering standards",
            kind: .mindset,
            techTags: [],
            triggers: [.always],
            advice: "Cutting features is not about lowering your standards. It's about focusing your standards on fewer things so each one actually works. Those 8 features that survived my cut? They got all my attention, all my testing, all my care. And they shipped. The 39 I cut would have spread that care so thin nothing would have been good enough.",
            oneLiner: "Fewer features means more care per feature.",
            caseStudyChapterId: "cs_codepet_mvp_ch1"
        ),

        KnowledgeEntry(
            id: "ak_ugly_prototype_insight",
            expertId: "expert_astro",
            label: "Ugly prototypes reveal truth",
            kind: .mindset,
            techTags: [],
            triggers: [.recentActivity("prototyping"), .projectStage("building")],
            advice: "My ugly Codepet prototype — gray rectangles, system fonts, no animations — told me the most important thing: the reward moment after completing a lesson felt genuinely satisfying even without polish. That ugly version revealed the truth about whether the idea works. Pretty mockups hide problems. Ugly prototypes expose them.",
            oneLiner: "Pretty mockups hide problems. Ugly prototypes expose them.",
            caseStudyChapterId: "cs_codepet_mvp_ch2"
        ),

        KnowledgeEntry(
            id: "ak_pixel_art_forgiving",
            expertId: "expert_astro",
            label: "Pixel art is forgiving",
            kind: .mindset,
            techTags: [],
            triggers: [.recentActivity("design"), .inactiveArea("art")],
            advice: "If you think you can't do the art for your project — try pixel art. The low resolution hides your lack of skill. The limited palette means you can't make ugly color choices. And players associate pixel art with charm, not cheapness. I'm not an artist. I've never taken a drawing class. But I made 8 characters in one afternoon because 16×16 with 4 colors makes it almost impossible to fail.",
            oneLiner: "Not an artist? Try 16×16 pixels. The constraints do the work for you.",
            caseStudyChapterId: "cs_codepet_mvp_ch3"
        ),
    ]
}
