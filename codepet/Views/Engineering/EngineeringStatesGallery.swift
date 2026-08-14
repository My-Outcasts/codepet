#if DEBUG
import SwiftUI

/// Every state an engineering run can be in, stacked in one window.
///
///   open <path>/codepet.app --args -CODEPET_MOCK_ENG_GALLERY YES
///
/// A launch arg, not `defaults write` — see `MockChat` for why that silently
/// does nothing to this app.
///
/// Why this exists rather than "just drive the mock": a live run shows ONE
/// state at a time and throws the previous one away. Copy is judged by
/// comparison — whether "Paused at its limit" reads differently enough from
/// "Didn't finish", whether the retry button appears in exactly the one place
/// it can succeed — and that comparison is impossible when the states are
/// minutes apart. It is also the only way to see the states a scripted run
/// cannot reach without a real backend refusing something.
///
/// **These are the real components driven into real states**, not mockups.
/// Every store below is a genuine `EngineeringRunStore` fed genuine
/// `EngineeringFrame`s through the same `handle` the SSE stream calls, and the
/// failure states are produced by an operation actually failing rather than by
/// assigning to `failure`. A gallery that faked its states would show copy
/// that no code path can produce — which is worse than no gallery, because it
/// looks like proof.
struct EngineeringStatesGallery: View {
    static let flagKey = "CODEPET_MOCK_ENG_GALLERY"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: flagKey) }

    private static let ask = "Add Stripe checkout so people can pay"

    @StateObject private var working = EngineeringRunStore(runner: GalleryRunner())
    @StateObject private var needsYou = EngineeringRunStore(runner: GalleryRunner())
    @StateObject private var ready = EngineeringRunStore(runner: GalleryRunner())
    @StateObject private var paused = EngineeringRunStore(runner: GalleryRunner())
    @StateObject private var unreachable = EngineeringRunStore(runner: GalleryRunner(diff: .unreachable))
    @StateObject private var reviewing = EngineeringRunStore(runner: GalleryRunner())

    @Environment(\.uiLanguage) private var lang
    @State private var reviewScope: ReviewScope = .branch

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                title

                section("1 · Working", "the tense carries the status: Working… while it runs, Worked for once it stops") {
                    EngineeringResultBar(store: working, elapsed: 41, onReview: {})
                }

                section("2 · Needs you",
                        "the run is stopped until this is answered. There is no phase chip any more — the unanswered card IS the signal") {
                    EngineeringResultBar(store: needsYou, onReview: {})
                }

                section("3 · Ready to review", "the only state with a diff to open") {
                    EngineeringResultBar(store: ready, elapsed: 118, onReview: {})
                }

                section("4 · Paused at its limit",
                        "NOT a failure — the work is intact, and no Resume button, because nothing can resume it") {
                    EngineeringResultBar(store: paused, elapsed: 240, onReview: {})
                }

                section("5 · Couldn't reach it",
                        "the ONE state that earns a retry. The worked line still reads as finished on purpose — the RUN succeeded, only the diff fetch failed, and calling the run failed would send you to re-run work that already landed") {
                    EngineeringResultBar(store: unreachable, onReview: {})
                }

                section("6 · The Review pane",
                        "scope fell back to the whole branch, and says so; a binary row shows counts, not an empty body") {
                    ReviewPane(store: reviewing, onScope: { scope in
                        reviewScope = scope
                        await reviewing.loadDiff(scope: scope)
                    })
                    .frame(height: 420)
                    .background(CodepetTheme.pageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodepetTheme.pageBackground)
        .task { await drive() }
    }

    // MARK: - driving each store into its state

    /// Each store is put into its state the way the app puts it there: frames
    /// through `handle`, and a real `loadDiff` for the two that show a diff.
    private func drive() async {
        working.handle(.step(ExecStep(id: "s1", label: "read the repository", done: true, kind: .mono)))
        working.handle(.step(ExecStep(id: "s2", label: "npm install stripe", done: false, kind: .mono)))

        needsYou.handle(.step(ExecStep(id: "s1", label: "read the repository", done: true, kind: .mono)))
        needsYou.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm install stripe")))

        // `start` first: `loadDiff` needs a runId, and taking one from
        // anywhere but a started run would be the gallery inventing state.
        await ready.start(ask: Self.ask)
        ready.handle(.message("Added Stripe checkout across three files. Tests pass."))
        ready.handle(.done(stopReason: "end_turn"))
        await ready.loadDiff(scope: .branch)

        await paused.start(ask: Self.ask)
        paused.handle(.step(ExecStep(id: "s1", label: "read the repository", done: true, kind: .mono)))
        paused.handle(.done(stopReason: "budget_reached"))

        // A real refusal from a real call — `record` is what arms the retry,
        // and assigning `failure` directly would show the button in a state
        // no code path produces. Finished FIRST, because that is when a diff
        // fetch actually fails: the run landed, and opening its diff did not.
        await unreachable.start(ask: Self.ask)
        unreachable.handle(.message("Added Stripe checkout across three files."))
        unreachable.handle(.done(stopReason: "end_turn"))
        await unreachable.loadDiff(scope: .branch)

        await reviewing.start(ask: Self.ask)
        reviewing.handle(.done(stopReason: "end_turn"))
        await reviewing.loadDiff(scope: .turn)   // .turn → falls back to the branch, flag set
    }

    // MARK: - chrome

    @ViewBuilder private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ENGINEERING · EVERY STATE")
                .font(CodepetTheme.inter(11, weight: .semibold)).tracking(0.6)
                .foregroundColor(CodepetTheme.accentBlue)
            Text("The real components, driven into real states. No network, no credits.")
                .font(CodepetTheme.inter(12))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }

    @ViewBuilder private func section(
        _ heading: String,
        _ note: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(CodepetTheme.inter(13, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(note)
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }
}

/// A runner that starts and then does nothing.
///
/// `MockEngineeringRunner` plays a timed script, which is right for walking
/// the flow and wrong here: the gallery needs each store held at ONE state,
/// and a script would move them off it a beat later. Its diff is reused
/// though — one canned diff, so the gallery and the walkthrough show the same
/// three files rather than two different fictions.
@MainActor
private final class GalleryRunner: EngineeringRunning {
    enum DiffOutcome { case succeeds, unreachable }

    private let diffOutcome: DiffOutcome
    init(diff: DiffOutcome = .succeeds) { self.diffOutcome = diff }

    func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String {
        "run_gallery"
    }

    func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {}

    func send(runId: String, turn: EngineeringTurn) async throws {}

    func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary {
        if case .unreachable = diffOutcome { throw EngineeringError.unavailable }
        return try await MockEngineeringRunner().diff(runId: runId, scope: scope)
    }
}

#Preview("Engineering — every state") {
    EngineeringStatesGallery()
        .environment(\.uiLanguage, .en)
        .frame(width: 620, height: 900)
}
#endif
