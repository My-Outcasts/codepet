import XCTest
@testable import codepet

/// The pinned block, and the one defect it can introduce.
///
/// `selectPriorWork` ALREADY ranks up to three Library deliverables into grounding on
/// every turn. Pin one of those and it lands twice — once at the 240-char automatic
/// excerpt and once at the 1200-char pinned excerpt. That does not emphasise it; it
/// tells the model there are two different documents with the same title. The
/// exclusion assertion below is the guard, and it is the reason this suite exists.
final class ChatContextPinTests: XCTestCase {

    /// A brief with enough in it that `BriefContext.compose` returns real text.
    /// Field names verified against `codepet/Models/CompanyBrief.swift` — it has
    /// `projectName`/`oneLiner`, not `name`/`idea`. Same two fields
    /// `ChatContextTests` uses.
    private func brief() -> CompanyBrief {
        CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion")
    }

    private func deliverable(id: String, title: String, body: String) -> Deliverable {
        Deliverable(id: id, kind: .doc, title: title, body: body, createdAt: "2026-08-20T10:00:00Z")
    }

    /// `TaskWho` is `does | draft | you` — there is no `.codepet` or `.founder`.
    private func task(id: String, title: String, detail: String = "") -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: detail, phase: .build, who: .does)
    }

    // MARK: - The regression guard

    /// **`pinned:` must be additive.** Every existing caller passes nothing, and the
    /// grounding they get must be byte-identical to what they got before this
    /// parameter existed. If this fails, every prompt in the app changed.
    func testEmptyPinnedChangesNothing() {
        let lib = [deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        let tasks = [task(id: "t1", title: "Ship billing")]
        let withDefault = ChatContext.compose(brief: brief(), tasks: tasks, library: lib, query: "pricing")
        let withEmpty = ChatContext.compose(brief: brief(), tasks: tasks, library: lib, query: "pricing",
                                            pinned: [])
        XCTAssertEqual(withDefault, withEmpty)
        XCTAssertFalse(withDefault.contains(ContextPin.groundingHeading),
                       "the pinned heading appeared with no pins")
        // The two assertions above cannot both be broken by one mistake — the
        // equality compares two calls down the SAME code path, so it stays green
        // however the pinned block is composed. What actually keeps `pinned: []`
        // free is `compose` skipping an EMPTY block: append it unconditionally and
        // every prompt in the app gains a blank line, silently, on every turn.
        // Measured: dropping the `if !pinnedBlock.isEmpty` guard left the other
        // eight tests here and all of ChatContextTests green. This is the assertion
        // that goes red for it.
        XCTAssertFalse(withDefault.contains("\n\n"),
                       "an empty block was joined into the grounding — blank line in every prompt")
    }

    // MARK: - The double-count guard

    /// The defect this design could introduce, asserted directly: a pinned
    /// deliverable's title appears ONCE in the grounding, not once per block.
    func testAPinnedDeliverableIsNotAlsoAutoSelected() {
        let lib = [
            deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro."),
            deliverable(id: "d2", title: "Launch checklist", body: "Freeze, then beta, then ship."),
        ]
        let out = ChatContext.compose(
            brief: brief(), tasks: [task(id: "t1", title: "Ship billing")],
            library: lib, query: "pricing",
            pinned: [.deliverable(id: "d1", title: "Pricing page")])

        let occurrences = out.components(separatedBy: "Pricing page").count - 1
        XCTAssertEqual(occurrences, 1,
                       "\"Pricing page\" appears \(occurrences) times — pinned AND auto-selected, "
                       + "which tells the model there are two documents with that title")
    }

    /// The exclusion is scoped to the pinned id and does not suppress the rest of
    /// the Library. An over-broad filter would quietly cost the founder grounding
    /// she was getting for free before she pinned anything.
    func testExcludingOnePinnedItemLeavesTheOthers() {
        let lib = [
            deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro."),
            deliverable(id: "d2", title: "Launch checklist", body: "Freeze, then beta, then ship."),
        ]
        let out = ChatContext.compose(
            brief: brief(), tasks: [], library: lib, query: "pricing launch",
            pinned: [.deliverable(id: "d1", title: "Pricing page")])
        XCTAssertTrue(out.contains("Launch checklist"),
                      "the unpinned deliverable was dropped too — the exclusion is over-broad")
    }

    /// A pinned TASK must not filter the Library. `deliverableId` is nil for a task,
    /// and if that ever changes an unrelated Library entry disappears.
    func testAPinnedTaskDoesNotFilterTheLibrary() {
        let lib = [deliverable(id: "t1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        // Same raw id as the deliverable, deliberately.
        let out = ChatContext.compose(
            brief: brief(), tasks: [task(id: "t1", title: "Ship billing")],
            library: lib, query: "pricing",
            pinned: [.task(id: "t1", title: "Ship billing")])
        XCTAssertTrue(out.contains("Pricing page"),
                      "a pinned task with a colliding id filtered a Library entry")
    }

    // MARK: - The block itself

    func testThePinnedBlockNamesTheHeadingAndTheItem() {
        let lib = [deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        let out = ChatContext.compose(brief: brief(), tasks: [], library: lib,
                                       pinned: [.deliverable(id: "d1", title: "Pricing page")])
        XCTAssertTrue(out.contains(ContextPin.groundingHeading))
        XCTAssertTrue(out.contains("Pricing page"))
        XCTAssertTrue(out.contains("We charge $20/mo for Pro."))
    }

    /// A pin gets more room than a guess — that is the whole difference between a
    /// choice and a ranking. 600 chars of body survives pinned; the automatic block
    /// would have clipped it at 240.
    func testAPinnedBodyGetsMoreRoomThanAnAutoSelectedOne() {
        let long = String(repeating: "pricing detail. ", count: 100)   // 1600 chars
        let lib = [deliverable(id: "d1", title: "Pricing page", body: long)]

        let auto = ChatContext.compose(brief: brief(), tasks: [], library: lib, query: "pricing")
        let pinned = ChatContext.compose(brief: brief(), tasks: [], library: lib, query: "pricing",
                                          pinned: [.deliverable(id: "d1", title: "Pricing page")])
        XCTAssertGreaterThan(pinned.count, auto.count + 800,
                             "the pinned excerpt is not meaningfully longer than the 240-char guess")
    }

    func testAPinnedTaskCarriesItsDetail() {
        let tasks = [task(id: "t1", title: "Ship billing", detail: "Stripe checkout, then the paywall.")]
        let out = ChatContext.compose(brief: brief(), tasks: tasks,
                                       pinned: [.task(id: "t1", title: "Ship billing")])
        XCTAssertTrue(out.contains(ContextPin.groundingHeading))
        XCTAssertTrue(out.contains("Stripe checkout, then the paywall."))
    }

    // MARK: - Error handling

    /// A pin whose target is gone contributes nothing and takes nothing down with
    /// it. This is reachable in the app: pin a deliverable, delete it in Library,
    /// then send. It must not render a heading over an empty list.
    func testAPinToADeletedItemIsSkippedEntirely() {
        let out = ChatContext.compose(brief: brief(), tasks: [], library: [],
                                       pinned: [.deliverable(id: "gone", title: "Deleted doc")])
        XCTAssertFalse(out.contains(ContextPin.groundingHeading),
                       "a heading was composed over zero resolvable pins")
        XCTAssertFalse(out.contains("Deleted doc"),
                       "the pin's cached title was sent as though the document still existed")
    }

    /// One resolvable pin among two still composes, carrying only what exists.
    func testAMissingPinDoesNotSuppressAResolvableOne() {
        let lib = [deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        let out = ChatContext.compose(
            brief: brief(), tasks: [], library: lib,
            pinned: [.deliverable(id: "gone", title: "Deleted doc"),
                     .deliverable(id: "d1", title: "Pricing page")])
        XCTAssertTrue(out.contains("Pricing page"))
        XCTAssertFalse(out.contains("Deleted doc"))
    }
}
