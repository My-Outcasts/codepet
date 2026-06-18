import Foundation
import Combine

// =============================================================================
// MARK: - Skill Challenge
// =============================================================================

/// A specific agentic-coding exercise the user can complete to practice a skill.
/// Each one is about directing an AI agent to make a change, then verifying its
/// work — not typing it from scratch. Challenges are project-aware: they
/// reference the user's actual project and files, and the AI auto-verifies
/// completion during coding sessions.
struct SkillChallenge: Identifiable, Codable, Equatable {
    let id: String
    let skillId: String            // e.g. "component_composition"
    let title: String              // Short name: "Extract a reusable component"
    let description: String        // What to do, referencing user's project
    let acceptanceCriteria: String // How the AI knows it's done
    let difficulty: ChallengeDifficulty
    let projectPath: String?       // Which project this applies to (nil = any)

    enum ChallengeDifficulty: String, Codable, Equatable {
        case starter    // First thing to try
        case practice   // Building the habit
        case stretch    // Pushing further
        case expert     // Mastery-level polish

        /// Progression order — exercises advance starter → expert.
        var order: Int {
            switch self {
            case .starter:  return 0
            case .practice: return 1
            case .stretch:  return 2
            case .expert:   return 3
            }
        }

        /// Bonus XP awarded for completing an exercise at this difficulty.
        var xpReward: Int {
            switch self {
            case .starter:  return 10
            case .practice: return 15
            case .stretch:  return 20
            case .expert:   return 25
            }
        }
    }
}

// =============================================================================
// MARK: - Challenge Progress
// =============================================================================

/// Tracks which challenges the user has completed.
final class ChallengeProgress: ObservableObject {

    @Published var completedChallengeIds: Set<String> = []
    @Published var activeChallenges: [SkillChallenge] = []

    private let completedKey = "cp_challenge_completed"
    private let activeKey = "cp_challenge_active"

    init() { load() }

    func isCompleted(_ challengeId: String) -> Bool {
        completedChallengeIds.contains(challengeId)
    }

    /// Marks a challenge complete. Returns `true` only when this is a NEW
    /// completion (it wasn't already done), so callers can award its XP exactly
    /// once regardless of which path (manual or auto-detected) triggered it.
    @discardableResult
    func markCompleted(_ challengeId: String) -> Bool {
        let (inserted, _) = completedChallengeIds.insert(challengeId)
        if inserted { save() }
        return inserted
    }

    func activeChallenges(for skillId: String) -> [SkillChallenge] {
        activeChallenges.filter { $0.skillId == skillId && !completedChallengeIds.contains($0.id) }
    }

    func completedChallenges(for skillId: String) -> [SkillChallenge] {
        activeChallenges.filter { $0.skillId == skillId && completedChallengeIds.contains($0.id) }
    }

    // MARK: - Linear progression (starter → expert)

    /// All of a skill's challenges, ordered by difficulty.
    func orderedChallenges(for skillId: String) -> [SkillChallenge] {
        activeChallenges
            .filter { $0.skillId == skillId }
            .sorted { $0.difficulty.order < $1.difficulty.order }
    }

    /// The first not-yet-completed challenge in order — the "up next" exercise.
    func upNext(for skillId: String) -> SkillChallenge? {
        orderedChallenges(for: skillId).first { !completedChallengeIds.contains($0.id) }
    }

    /// A challenge is unlocked once every earlier-ordered challenge is complete.
    func isUnlocked(_ challenge: SkillChallenge) -> Bool {
        let ordered = orderedChallenges(for: challenge.skillId)
        guard let idx = ordered.firstIndex(where: { $0.id == challenge.id }) else { return false }
        return ordered.prefix(idx).allSatisfy { completedChallengeIds.contains($0.id) }
    }

    /// The next unlocked, incomplete challenge after this one — drives "Next".
    func nextChallenge(after challenge: SkillChallenge) -> SkillChallenge? {
        let ordered = orderedChallenges(for: challenge.skillId)
        guard let idx = ordered.firstIndex(where: { $0.id == challenge.id }) else { return nil }
        return ordered.dropFirst(idx + 1).first { !completedChallengeIds.contains($0.id) }
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(Array(completedChallengeIds), forKey: completedKey)
        if let data = try? JSONEncoder().encode(activeChallenges) {
            UserDefaults.standard.set(data, forKey: activeKey)
        }
    }

    func load() {
        completedChallengeIds = Set(UserDefaults.standard.stringArray(forKey: completedKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: activeKey),
           let challenges = try? JSONDecoder().decode([SkillChallenge].self, from: data) {
            activeChallenges = challenges
        }
    }

    func resetAll() {
        completedChallengeIds.removeAll()
        activeChallenges.removeAll()
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: activeKey)
    }
}

// =============================================================================
// MARK: - Challenge Generator
// =============================================================================

/// Generates project-specific challenges based on the user's actual projects.
enum ChallengeGenerator {

    /// Generate challenges for a skill, personalized to the user's project.
    static func generate(
        skillId: String,
        projectName: String,
        projectPath: String
    ) -> [SkillChallenge] {
        switch skillId {
        case "component_composition":
            return [
                SkillChallenge(
                    id: "cc_extract_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Extract a reusable component",
                    description: "Point your agent at the largest section in your \(projectName) project and have it move that into its own file — then check it imports back and works on its own.",
                    acceptanceCriteria: "A new file holds the extracted code and imports back into the main file cleanly — the page works exactly as before",
                    difficulty: .starter,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "cc_shared_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Create a shared utility",
                    description: "Ask your agent to find code duplicated in at least 2 places in \(projectName) and pull it into one shared helper — then confirm both callers actually use it now.",
                    acceptanceCriteria: "Duplicated code now lives in one shared utility file, and every place that needed it calls that instead",
                    difficulty: .practice,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "cc_three_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Split into 3+ components",
                    description: "Have your agent break one large file in \(projectName) into at least 3 smaller, focused files — then review that each one really does a single thing well.",
                    acceptanceCriteria: "One large file is split into 3 or more focused component files, each doing a single thing",
                    difficulty: .stretch,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "cc_props_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Make a component reusable with props",
                    description: "Get your agent to add props to a component in \(projectName) so the same one renders different content (e.g. a card that takes a title and image) — then verify it actually renders two different cases.",
                    acceptanceCriteria: "A component accepts props and renders different data — reused in at least two places, not copy-pasted",
                    difficulty: .expert,
                    projectPath: projectPath
                ),
            ]

        case "loading_error_states":
            return [
                SkillChallenge(
                    id: "le_trycatch_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add your first try-catch",
                    description: "Have your agent wrap a data load or API call in \(projectName) in a try-catch with a helpful error message — then read the diff to see exactly what it does on failure.",
                    acceptanceCriteria: "A data loading function is wrapped in try-catch and fails with a clear, friendly error message instead of breaking",
                    difficulty: .starter,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "le_spinner_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add a loading spinner",
                    description: "Ask your agent to add a loading indicator to \(projectName) that shows while data is being fetched — then throttle your network and confirm you actually see it.",
                    acceptanceCriteria: "A loading spinner or indicator shows while data is being fetched, then clears once it arrives",
                    difficulty: .practice,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "le_fallback_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Build a fallback UI",
                    description: "Have your agent show a friendly error screen with a retry button when something breaks in \(projectName), instead of a crash or blank page — then force an error to test it fires.",
                    acceptanceCriteria: "When something fails, a friendly error state with a retry option shows — no crash, no blank page",
                    difficulty: .stretch,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "le_retry_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add a working retry button",
                    description: "Get your agent to let users retry a failed load in place in \(projectName) — then verify it re-attempts the request without reloading the whole page.",
                    acceptanceCriteria: "A failed load can be retried in place — the retry action re-attempts the request without a full page reload",
                    difficulty: .expert,
                    projectPath: projectPath
                ),
            ]

        case "form_validation_ux":
            return [
                SkillChallenge(
                    id: "fv_required_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Validate required fields",
                    description: "Have your agent add required-field checks to a form in \(projectName) before submit — then try submitting it empty and confirm it's blocked.",
                    acceptanceCriteria: "Required fields are validated before submit, and an empty form is blocked with a clear message",
                    difficulty: .starter,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "fv_realtime_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add real-time validation",
                    description: "Ask your agent to validate as the user types in \(projectName), with inline messages by each field — then you judge whether it feels helpful, not naggy.",
                    acceptanceCriteria: "The form runs real-time inline validation that triggers on input change, with per-field messages",
                    difficulty: .practice,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "fv_format_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Validate data formats",
                    description: "Have your agent add format checks to \(projectName) — positive numbers, real emails, sensible dates — then throw bad input at it to confirm each one catches.",
                    acceptanceCriteria: "Inputs have format validation for specific data types — positive numbers, real emails, sensible dates — and bad input is caught",
                    difficulty: .stretch,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "fv_success_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Show a success state",
                    description: "Get your agent to show a clear confirmation after a successful submit in \(projectName) and disable the form so it can't be sent twice — then verify you can't fire it twice.",
                    acceptanceCriteria: "A successful submit shows a clear confirmation and the form can't be sent twice — duplicate submission is prevented",
                    difficulty: .expert,
                    projectPath: projectPath
                ),
            ]

        case "accessibility_basics":
            return [
                SkillChallenge(
                    id: "ab_alt_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add alt text to images",
                    description: "Have your agent add descriptive alt text to every image in \(projectName) — then spot-check a few read like a human wrote them, not 'image123'.",
                    acceptanceCriteria: "Every image carries descriptive alt text attributes a screen reader can read aloud",
                    difficulty: .starter,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "ab_keyboard_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Make it keyboard navigable",
                    description: "Ask your agent to make every interactive element in \(projectName) reachable with just Tab and Enter — then put the mouse down and try it yourself.",
                    acceptanceCriteria: "Every interactive element is reachable with keyboard navigation — sensible tab order and enter handlers, works end to end",
                    difficulty: .practice,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "ab_aria_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add aria-labels to buttons",
                    description: "Have your agent add aria-labels to the icon buttons in \(projectName) — then confirm a screen reader would announce what each one actually does.",
                    acceptanceCriteria: "Icon buttons have aria-label attributes so a screen reader announces what each interactive element does",
                    difficulty: .stretch,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "ab_focus_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add visible focus styles",
                    description: "Get your agent to add clear focus-visible outlines to links, inputs and buttons in \(projectName) — then Tab through and watch the focus actually move.",
                    acceptanceCriteria: "Links, inputs and buttons show visible focus indicators as you tab through the interactive elements",
                    difficulty: .expert,
                    projectPath: projectPath
                ),
            ]

        case "responsive_layout":
            return [
                SkillChallenge(
                    id: "rl_stack_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Stack the hero on mobile",
                    description: "Have your agent make the hero in \(projectName) stack vertically on narrow screens — then drag the window narrow yourself and confirm nothing overflows.",
                    acceptanceCriteria: "Responsive styles make the hero stack cleanly on small screens — nothing overflows or shrinks awkwardly",
                    difficulty: .starter,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "rl_list_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Make the list reflow",
                    description: "Ask your agent to turn a list or grid in \(projectName) multi-column on desktop and single-column on phones — then resize to check the reflow yourself.",
                    acceptanceCriteria: "A responsive grid or flex layout reflows by screen width — multi-column on desktop, single-column on phones",
                    difficulty: .practice,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "rl_form_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Make the form touch-friendly",
                    description: "Have your agent make a form in \(projectName) full-width with thumb-sized inputs and buttons on phones — then test the tap targets at mobile width.",
                    acceptanceCriteria: "The form layout is responsive and touch-friendly on small screens — full-width with thumb-sized inputs",
                    difficulty: .stretch,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "rl_breakpoints_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Add consistent breakpoints",
                    description: "Get your agent to give \(projectName) consistent breakpoints across phone, tablet and desktop — then review that the page looks intentional, not patched per-element.",
                    acceptanceCriteria: "Consistent responsive breakpoints make the whole page look intentional at phone, tablet and desktop widths",
                    difficulty: .expert,
                    projectPath: projectPath
                ),
            ]

        case "performance":
            return [
                SkillChallenge(
                    id: "pf_images_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Optimize the images",
                    description: "Have your agent swap raw <img> tags in \(projectName) for the framework's optimized image component — then confirm every image still renders correctly.",
                    acceptanceCriteria: "Raw img tags are converted to the optimized image component, and every image still renders correctly",
                    difficulty: .starter,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "pf_dimensions_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Stop layout shift",
                    description: "Ask your agent to give every image in \(projectName) explicit width and height — then reload on a slow connection and watch the page hold still.",
                    acceptanceCriteria: "Every image declares explicit dimensions so the page holds still and layout shift is prevented as images load",
                    difficulty: .practice,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "pf_lazy_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Lazy-load offscreen content",
                    description: "Have your agent defer offscreen images or sections in \(projectName) that aren't visible on first paint — then verify first paint is faster, not that something broke below the fold.",
                    acceptanceCriteria: "Offscreen images or content are lazy-loaded so the first paint shows up faster",
                    difficulty: .stretch,
                    projectPath: projectPath
                ),
                SkillChallenge(
                    id: "pf_firstpaint_\(projectPath.hashValue)",
                    skillId: skillId,
                    title: "Trim the first paint",
                    description: "Get your agent to find and defer anything heavy loading up front in \(projectName) — then measure first render before and after, don't just eyeball it.",
                    acceptanceCriteria: "Heavy up-front work is deferred or removed, reducing what loads on initial render so first paint is measurably faster",
                    difficulty: .expert,
                    projectPath: projectPath
                ),
            ]

        default:
            return []
        }
    }

    /// Generate challenges for all skills based on the user's most active project.
    static func generateAll(
        projectName: String,
        projectPath: String
    ) -> [SkillChallenge] {
        let skillIds = [
            "component_composition",
            "loading_error_states",
            "form_validation_ux",
            "accessibility_basics",
            "responsive_layout",
            "performance"
        ]
        return skillIds.flatMap { generate(skillId: $0, projectName: projectName, projectPath: projectPath) }
    }
}

// =============================================================================
// MARK: - Challenge Matcher
// =============================================================================

/// Checks if a detected skill from a coding session matches an active challenge.
enum ChallengeMatcher {

    /// Given a detected skill and its evidence, find if any active challenge was completed.
    static func findCompletedChallenges(
        detectedSkill: DetectedSkill,
        activeChallenges: [SkillChallenge]
    ) -> [SkillChallenge] {
        let matching = activeChallenges.filter { challenge in
            guard challenge.skillId == detectedSkill.skillId else { return false }
            guard detectedSkill.confidence == "strong" else { return false }

            // Check if the evidence text relates to the challenge's acceptance criteria
            let evidence = detectedSkill.evidence.lowercased()
            let criteria = challenge.acceptanceCriteria.lowercased()

            // Simple keyword matching — check if key phrases from criteria appear in evidence
            let criteriaWords = criteria.components(separatedBy: .whitespaces)
                .filter { $0.count > 4 } // skip short words
            let matchCount = criteriaWords.filter { evidence.contains($0) }.count
            let matchRatio = criteriaWords.isEmpty ? 0 : Double(matchCount) / Double(criteriaWords.count)

            return matchRatio > 0.3 // 30% keyword overlap = likely match
        }
        return matching
    }
}
