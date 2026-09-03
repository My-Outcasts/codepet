// codepetTests/UpstreamCreditTests.swift
import XCTest
@testable import codepet

@MainActor
final class UpstreamCreditTests: XCTestCase {

    private func work(_ title: String, unapproved: Bool = false) -> UpstreamWork {
        UpstreamWork(taskTitle: title, deptName: "Design", petName: "Luna",
                     kind: "doc", body: "B", unapproved: unapproved)
    }

    // MARK: - The credit line

    /// Absent, not empty: a first task must not be decorated with a blank row.
    func testNoLineWithoutUpstream() {
        XCTAssertNil(UpstreamCredit.line([]))
    }

    func testNamesThePetAndTheWork() {
        let line = UpstreamCredit.line([work("brand direction")])
        XCTAssertEqual(line, "Built on Luna\'s \u{201C}brand direction\u{201D}")
    }

    /// The fixture in every other test here is a tidy noun phrase ("brand direction") and a
    /// REAL `taskTitle` is not: it is a deliverable's title, and `buildDeliverable` falls back
    /// to the task's own name, so what actually arrives is "Shape the Murror visual
    /// direction". Unquoted, the possessive read "Built on Luna\'s Shape the Murror visual
    /// direction". Found by rendering the row to a PNG and reading it — no fixture written for
    /// this feature could have failed, which is why this one uses the fixture\'s own string.
    func testASentenceTitleStillReadsAsASentence() throws {
        let real = DemoProject.murror.tasks.first { $0.id == "mur-brand" }!.title
        XCTAssertEqual(real, "Shape the Murror visual direction", "fixture moved; update this")
        let line = try XCTUnwrap(UpstreamCredit.line([work(real)]))
        XCTAssertFalse(line.contains("Luna\'s Shape"),
                       "an imperative title needs quoting, not a possessive: \(line)")
        XCTAssertTrue(line.contains("\u{201C}\(real)\u{201D}"), line)
    }

    /// The founder decision: a chained run passes the draft forward unapproved and the card
    /// SAYS so. Hiding it is the fixture-lie failure mode this codebase keeps paying for.
    func testSaysWhenTheDraftIsUnapproved() throws {
        let line = try XCTUnwrap(UpstreamCredit.line([work("brand direction", unapproved: true)]))
        XCTAssertTrue(line.contains("unapproved draft"), line)
    }

    /// The plan asked for `contains("2")` here while specifying the copy as
    /// `"... + 1 more"` — the two cannot both hold, and the copy is the one worth keeping
    /// (naming the first contribution and counting the rest is the standard idiom). So the
    /// count is asserted where it actually varies: two items say "1 more", three say "2 more".
    /// `contains("2")` would also have passed on a line that happened to contain a 2 for any
    /// other reason, which is not a guard.
    func testCountsTheContributionsItDidNotName() throws {
        let two = try XCTUnwrap(UpstreamCredit.line([work("brand direction"), work("the scan")]))
        // The quotes are CURLY (U+201C/D). `contains("Luna's brand direction")` was the
        // assertion here and it went red the moment the title got quoted — the same
        // straight-vs-curly trap this repo has paid for before.
        XCTAssertTrue(two.contains("Luna's \u{201C}brand direction\u{201D}"), two)
        XCTAssertTrue(two.contains("1 more"), two)

        let three = try XCTUnwrap(
            UpstreamCredit.line([work("brand direction"), work("the scan"), work("the model")]))
        XCTAssertTrue(three.contains("2 more"), three)
    }

    /// Unapproved anywhere in the set, not only first: the founder is being told that
    /// something under this card was not approved, and which position it arrived in is
    /// not something they can see.
    func testTheUnapprovedNoteSurvivesASummary() throws {
        let line = try XCTUnwrap(
            UpstreamCredit.line([work("brand direction"), work("the scan", unapproved: true)]))
        XCTAssertTrue(line.contains("unapproved draft"), line)
    }

    // MARK: - Choosing what to chain

    func testFirstUnfiledDependencyIsTheOneWithNoDeliverable() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!   // dependsOn brand, landscape
        let brandFiled = Deliverable(id: "d1", kind: .doc, title: "Brand", body: "B",
                                     sourceTaskId: "mur-brand")
        let dep = UpstreamWork.firstUnfiled(dependencyOf: site, in: tasks, library: [brandFiled])
        XCTAssertEqual(dep?.id, "mur-landscape", "brand is filed, so the scan is what's missing")

        let both = [brandFiled,
                    Deliverable(id: "d2", kind: .doc, title: "Scan", body: "S",
                                sourceTaskId: "mur-landscape")]
        XCTAssertNil(UpstreamWork.firstUnfiled(dependencyOf: site, in: tasks, library: both),
                     "nothing to chain when every dependency is already filed")
    }

    /// A chained upstream draft is NOT in the library — that is the whole point of it being a
    /// draft — so `assemble` cannot see it and the item has to be built from the draft itself.
    func testFromDraftCarriesTheDepartmentAndMarksItUnapproved() {
        let brand = DemoProject.murror.tasks.first { $0.id == "mur-brand" }!
        let draft = Deliverable(id: "d", kind: .doc, title: "Brand direction", body: "Navy.",
                                sourceTaskId: "mur-brand")
        let w = UpstreamWork.fromDraft(draft, task: brand)
        XCTAssertEqual(w.taskTitle, "Brand direction")
        XCTAssertEqual(w.deptName, "Design")
        XCTAssertEqual(w.petName, "Luna")
        XCTAssertTrue(w.unapproved, "a draft that skipped approval must say so")
    }

    // MARK: - The chain, through the store

    private func murrorStore(
        reply: CompanyChatReply? = nil,
        runner: @escaping (RunTaskRequest) async -> RunTaskResponse?
    ) -> CompanyStore {
        // Same stubs as `CompanyStoreChatRunTests`: the live defaults reach Firestore and
        // Firebase Auth, both of which trap under an unconfigured `FirebaseApp`.
        CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .building,
                         companionId: "byte", onboardedAt: Date(),
                         tasks: DemoProject.murror.tasks)
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in reply },
           chatStreamer: { _ in
               AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
           },
           taskRunner: runner, librarySaver: { _, _ in true },
           decisionExtractor: { _, _ in [] })
    }

    override func setUp() {
        super.setUp()
        CompanyStore.execStepNanos = 0
        CompanyStore.execDoneBeatNanos = 0
    }

    /// The founder decision, end to end: `[Run both]` runs the missing upstream task first
    /// and the downstream run RECEIVES it — unapproved, with no approval gate between them.
    func testChainRunsUpstreamThenDownstreamAndFeedsItForward() async {
        let seen = Recorder()
        let s = murrorStore(runner: { req in
            await seen.record(req)
            return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# \(req.taskTitle)")
        })
        await s.hydrate(companyId: "u")
        await s.runChained(taskId: "mur-site", language: .en)

        let requests = await seen.requests
        XCTAssertEqual(requests.map(\.taskId), ["mur-brand", "mur-site"],
                       "the dependency runs first, then the task the founder asked for")
        XCTAssertNil(requests[0].upstream, "nothing is filed yet, so the first run carries nothing")
        let up = requests[1].upstream ?? []
        XCTAssertEqual(up.count, 1)
        XCTAssertEqual(up.first?.deptName, "Design")
        XCTAssertEqual(up.first?.petName, "Luna")
        XCTAssertTrue(up.first?.unapproved ?? false,
                      "a chained run passes the draft forward unapproved and says so")
        XCTAssertTrue(up.first?.body.contains("Shape the Murror visual direction") ?? false,
                      "the DRAFT's body has to travel, not just its title")
    }

    /// What the card says is read off the request that was actually sent, so the credit and
    /// the prompt cannot disagree. Deriving it a second time for the view is how a card ends
    /// up crediting work the model never received.
    func testTheCardCreditsExactlyWhatTheRunWasSent() async {
        let seen = Recorder()
        let s = murrorStore(runner: { req in
            await seen.record(req)
            return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# \(req.taskTitle)")
        })
        await s.hydrate(companyId: "u")
        await s.runChained(taskId: "mur-site", language: .en)

        let requests = await seen.requests
        let cards = s.chatMessages.filter { $0.draft != nil }
        XCTAssertEqual(cards.count, 2, "two cards land, in order")
        XCTAssertNil(cards[0].upstream, "the upstream card itself credits nothing")
        XCTAssertEqual(cards[1].upstream, requests[1].upstream)
        let line = UpstreamCredit.line(cards[1].upstream ?? [])
        XCTAssertTrue(line?.contains("unapproved draft") ?? false, line ?? "nil")
    }

    /// The common case has to stay untouched: a task with no dependencies gets no credit row.
    func testAnOrdinaryRunCreditsNothing() async {
        let s = murrorStore(runner: { req in
            RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# done")
        })
        await s.hydrate(companyId: "u")
        await s.runChained(taskId: "mur-landscape", language: .en)   // dependsOn is empty
        let cards = s.chatMessages.filter { $0.draft != nil }
        XCTAssertEqual(cards.count, 1, "no dependency, no chained run")
        XCTAssertNil(cards[0].upstream)
        XCTAssertNil(UpstreamCredit.line(cards[0].upstream ?? []))
    }

    // MARK: - The offer

    /// A dependency arrow pointing at nothing must not be run through silently. The founder
    /// gets the choice, and — the part worth pinning — NOTHING runs until they make it.
    func testARunWithAnUnfiledDependencyOffersTheChainAndRunsNothing() async {
        let seen = Recorder()
        let s = murrorStore(reply: CompanyChatReply(text: "On it", runTaskId: "mur-site"),
                            runner: { req in
            await seen.record(req)
            return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# x")
        })
        await s.hydrate(companyId: "u")
        await s.sendChat("build the landing page", language: .en)

        let offer = s.chatMessages.compactMap(\.chainOffer).first
        XCTAssertEqual(offer?.taskId, "mur-site")
        XCTAssertEqual(offer?.upstreamTaskId, "mur-brand", "the first unfiled dependency")
        XCTAssertEqual(offer?.upstreamPetName, "Luna")
        let requests = await seen.requests
        XCTAssertTrue(requests.isEmpty, "a run that spends credits must wait for the founder")
        XCTAssertTrue(s.chatMessages.allSatisfy { $0.draft == nil })
    }

    func testRunBothChainsAndJustMineDoesNot() async {
        for (chained, expected) in [(true, ["mur-brand", "mur-site"]), (false, ["mur-site"])] {
            let seen = Recorder()
            let s = murrorStore(reply: CompanyChatReply(text: "On it", runTaskId: "mur-site"),
                                runner: { req in
                await seen.record(req)
                return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# x")
            })
            await s.hydrate(companyId: "u")
            await s.sendChat("build the landing page", language: .en)
            let id = try! XCTUnwrap(s.chatMessages.first { $0.chainOffer != nil }?.id)

            if chained { await s.confirmChain(messageId: id, language: .en) }
            else { await s.declineChain(messageId: id, language: .en) }

            let requests = await seen.requests
            XCTAssertEqual(requests.map(\.taskId), expected, "chained: \(chained)")
            if !chained {
                XCTAssertNil(requests.first?.upstream,
                             "\"Just mine\" must not smuggle the upstream work in anyway")
            }
        }
    }

    /// Pressing twice must not run twice — the guard `runProposal` already has, on a card
    /// where a double tap would spend two runs instead of one.
    func testTheOfferIsConsumedOnce() async {
        let seen = Recorder()
        let s = murrorStore(reply: CompanyChatReply(text: "On it", runTaskId: "mur-site"),
                            runner: { req in
            await seen.record(req)
            return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# x")
        })
        await s.hydrate(companyId: "u")
        await s.sendChat("build the landing page", language: .en)
        let id = try! XCTUnwrap(s.chatMessages.first { $0.chainOffer != nil }?.id)
        await s.declineChain(messageId: id, language: .en)
        await s.declineChain(messageId: id, language: .en)
        await s.confirmChain(messageId: id, language: .en)
        let requests = await seen.requests
        XCTAssertEqual(requests.map(\.taskId), ["mur-site"])
    }

    /// An actor, not a captured array: `taskRunner` is called from the store's own tasks and
    /// a plain `var` would be a data race the compiler is right to reject.
    private actor Recorder {
        var requests: [RunTaskRequest] = []
        func record(_ r: RunTaskRequest) { requests.append(r) }
    }
}
