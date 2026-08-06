// codepetTests/ChatContextTests.swift
import XCTest
@testable import codepet

final class ChatContextTests: XCTestCase {
    func testComposeIncludesBriefNextStepAndProgress() {
        let brief = CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion")
        let tasks = [
            RoadmapTask(id: "a", title: "Interview users", detail: "", phase: .find, who: .you),
            RoadmapTask(id: "b", title: "Ship auth", detail: "", phase: .build, who: .does, done: true),
        ]
        let ctx = ChatContext.compose(brief: brief, tasks: tasks)
        XCTAssertTrue(ctx.contains("Codepet"))          // brief signal
        XCTAssertTrue(ctx.contains("Interview users"))  // next step / open task
        XCTAssertTrue(ctx.contains("%"))                // progress
    }
    func testComposeEmptyStillNonEmpty() {
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: [])
        XCTAssertFalse(ctx.isEmpty)
        XCTAssertTrue(ctx.contains("No brief yet"))
    }
    /// `createdAt` is pinned on both sides: it joined the struct in `f0f9253` and the synthesized
    /// `Equatable` began comparing a timestamp taken at construction, so two messages built one
    /// statement apart were never equal. This suite went red then and stayed red — the sibling fix
    /// in `CopilotMessageDraftTests` on Aug 6 missed it, because I fixed the suite I was running
    /// rather than grepping for the pattern.
    func testCopilotMessageIdentityAndEquatable() {
        let t = Date(timeIntervalSince1970: 1_754_400_000)
        let m = CopilotMessage(id: "1", role: .me, createdAt: t, text: "hi")
        XCTAssertEqual(m.id, "1")
        XCTAssertEqual(m, CopilotMessage(id: "1", role: .me, createdAt: t, text: "hi"))
        XCTAssertNotEqual(m, CopilotMessage(id: "2", role: .companion, createdAt: t, text: "hi"))
    }

    // MARK: - selectPriorWork

    func testSelectPriorWorkRanksByQueryOverlap() {
        let relevant = Deliverable(id: "1", kind: .doc, title: "Pricing strategy",
                                    body: "We priced the subscription at $9 per month for early adopters.",
                                    createdAt: "2026-01-01T00:00:00Z")
        let unrelated = Deliverable(id: "2", kind: .post, title: "Launch tweet",
                                     body: "Excited to announce our new mascot artwork today.",
                                     createdAt: "2026-01-02T00:00:00Z")
        let picked = ChatContext.selectPriorWork([unrelated, relevant], query: "What was our pricing subscription plan?")
        XCTAssertEqual(picked.first?.id, "1", "the deliverable sharing words with the query should rank first")
    }

    func testSelectPriorWorkNilQueryFallsBackToMostRecent() {
        let older = Deliverable(id: "old", kind: .doc, title: "Old doc", body: "some body text",
                                 createdAt: "2026-01-01T00:00:00Z")
        let newer = Deliverable(id: "new", kind: .doc, title: "New doc", body: "some body text",
                                 createdAt: "2026-02-01T00:00:00Z")
        let picked = ChatContext.selectPriorWork([older, newer], query: nil)
        XCTAssertEqual(picked.map { $0.id }, ["new", "old"])
    }

    func testSelectPriorWorkCapsAtMax() {
        let items = (0..<10).map { i in
            Deliverable(id: "\(i)", kind: .doc, title: "Doc \(i)", body: "body \(i)",
                        createdAt: "2026-01-0\(i)T00:00:00Z")
        }
        let picked = ChatContext.selectPriorWork(items, query: nil, max: 3)
        XCTAssertEqual(picked.count, 3)
    }

    // MARK: - compose richer grounding

    func testComposeIncludesDepartmentLineWhenTasksHaveDepts() {
        let brief = CompanyBrief(projectName: "Codepet")
        let tasks = [
            RoadmapTask(id: "a", title: "Ship auth", detail: "", phase: .build, who: .does, dept: "eng"),
        ]
        let ctx = ChatContext.compose(brief: brief, tasks: tasks)
        XCTAssertTrue(ctx.contains("Departments:"))
        XCTAssertTrue(ctx.contains("Engineering"))
        XCTAssertTrue(ctx.contains("Ship auth"))
    }

    func testComposeIncludesPriorWorkExcerptWhenLibraryNonEmpty() {
        let brief = CompanyBrief(projectName: "Codepet")
        let deliverable = Deliverable(id: "1", kind: .doc, title: "Pricing strategy",
                                       body: "We priced the subscription at $9 per month.",
                                       createdAt: "2026-01-01T00:00:00Z")
        let ctx = ChatContext.compose(brief: brief, tasks: [], library: [deliverable], query: "pricing")
        XCTAssertTrue(ctx.contains("Already-shipped work"))
        XCTAssertTrue(ctx.contains("Pricing strategy"))
    }

    func testComposeUnchangedForEmptyCase() {
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: [])
        XCTAssertTrue(ctx.contains("No brief yet"))
        XCTAssertTrue(ctx.contains("Roadmap progress:"))
        XCTAssertFalse(ctx.contains("Open tasks:"))
        XCTAssertFalse(ctx.contains("Departments:"))
        XCTAssertFalse(ctx.contains("Already-shipped work"))
        XCTAssertFalse(ctx.contains("cannot run any roadmap task"))   // no roadmap, nothing to explain
    }

    // MARK: - "you cannot run anything this turn"

    /// THIS TEST WAS RED on the branch and nobody noticed. It was written when one open
    /// founder-owned step shut every later phase, so with `a` open nothing was runnable. The Aug 5
    /// gating change ended that — a founder step no longer gates — which makes `b` runnable and the
    /// gate correctly silent. Rewritten to the state that now produces an empty runnable set: a
    /// task the founder owns, with nothing else open.
    func testGroundingNamesTheFoundersOwnStepWhenThatIsAllThatIsLeft() {
        let tasks = [
            RoadmapTask(id: "a", title: "Talk to 5 potential users", detail: "", phase: .find, who: .you),
        ]
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
        XCTAssertTrue(ctx.contains("cannot run any roadmap task"))
        XCTAssertTrue(ctx.contains("\"Talk to 5 potential users\" is the founder's own step"))
        XCTAssertTrue(ctx.contains("do NOT say you are on it"))
        XCTAssertTrue(ctx.contains("walk them through"))
    }

    /// A founder-owned step no longer shuts the phases behind it, so work Codepet CAN do stays
    /// runnable and the gate must stay quiet. This is the state the old version of the test above
    /// asserted the opposite of.
    func testAFounderOwnedStepDoesNotSilenceTheRestOfTheRoadmap() {
        let tasks = [
            RoadmapTask(id: "a", title: "Talk to 5 potential users", detail: "", phase: .find, who: .you),
            RoadmapTask(id: "b", title: "Draft the landing page", detail: "", phase: .build, who: .does),
        ]
        XCTAssertFalse(ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
                        .contains("cannot run any roadmap task"))
    }

    // MARK: - A draft awaiting approval is NOT "the founder's own step"

    /// The Aug 6 failure, pinned.
    ///
    /// Two drafts Codepet had produced sat waiting for approval, holding Build shut. The gate
    /// reached for `blockingDraft` — which returns an unapproved DRAFT — and told the model it was
    /// "the founder's own step" the roadmap was waiting on her to FINISH, then told it to offer a
    /// walkthrough. So Codepet said "I can't produce these tasks for you outright — building the
    /// company is your work" about work the roadmap marks Codepet-can-do, and hand-wrote the
    /// deliverable in chat. The one unblocking move — approve, one click — was never mentioned.
    func testADraftAwaitingApprovalAsksForApprovalNotForTheFounderToDoIt() {
        let tasks = [
            RoadmapTask(id: "a", title: "Write your landing page copy", detail: "", phase: .find,
                        who: .does, drafted: true),
            RoadmapTask(id: "b", title: "Set up a waitlist signup", detail: "", phase: .build,
                        who: .does, dependsOn: ["a"]),
        ]
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
        XCTAssertTrue(ctx.contains("cannot run any roadmap task"))
        XCTAssertTrue(ctx.contains("\"Write your landing page copy\" is work YOU already drafted"))
        XCTAssertTrue(ctx.contains("waiting for the founder's approval"))
        XCTAssertTrue(ctx.contains("review and approve"))
        // The two instructions that produced the wrong reply must be absent for this cause.
        XCTAssertFalse(ctx.contains("the founder's own step"),
                       "a draft Codepet produced is not the founder's work")
        // The AFFIRMATIVE form only. The draft branch deliberately contains the words "Do NOT
        // offer to walk them through it", so a bare substring check on "walk them through" passes
        // for the wrong reason — and it did, which is how this assertion caught itself.
        XCTAssertFalse(ctx.contains("then offer to walk them through"),
                       "there is nothing to walk through — the work is done and waiting")
        XCTAssertTrue(ctx.contains("Do NOT offer to walk them through"))
    }

    /// It must say what approving buys, or "approve this" is just another chore.
    func testTheGateSaysHowManyTasksTheApprovalUnblocks() {
        let tasks = [
            RoadmapTask(id: "a", title: "Write your landing page copy", detail: "", phase: .find,
                        who: .does, drafted: true),
            RoadmapTask(id: "b", title: "Waitlist", detail: "", phase: .build, who: .does, dependsOn: ["a"]),
            RoadmapTask(id: "c", title: "Cold outreach", detail: "", phase: .build, who: .does, dependsOn: ["a"]),
        ]
        XCTAssertTrue(ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
                        .contains("unblocks 2 later tasks"))
    }

    /// A draft blocking nothing downstream still needs approving — it just must not claim to
    /// unblock work that does not exist.
    func testADraftThatUnblocksNothingClaimsNothing() {
        let tasks = [
            RoadmapTask(id: "a", title: "Write your landing page copy", detail: "", phase: .find,
                        who: .does, drafted: true),
        ]
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
        XCTAssertTrue(ctx.contains("already drafted"))
        XCTAssertFalse(ctx.contains("unblocks"))
    }

    /// The opposite state must stay silent: one runnable task means the CF gets `run_task`,
    /// so telling the model it cannot run anything would be a lie in the other direction.
    func testGroundingStaysSilentWhenSomethingIsRunnable() {
        let tasks = [
            RoadmapTask(id: "a", title: "Draft the landing page", detail: "", phase: .find, who: .does),
        ]
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
        XCTAssertFalse(ctx.contains("cannot run any roadmap task"))
    }

    /// Every task done — nothing runnable, but no founder step holding anything either. The
    /// gate still fires (there is genuinely nothing to run) and must not invent a blocker.
    func testGroundingOmitsTheBlockerClauseWhenNoStepIsHoldingTheWindow() {
        let tasks = [
            RoadmapTask(id: "a", title: "Interview users", detail: "", phase: .find, who: .you, done: true),
        ]
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
        XCTAssertTrue(ctx.contains("cannot run any roadmap task"))
        XCTAssertFalse(ctx.contains("own step"))
    }
}
