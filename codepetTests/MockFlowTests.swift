// codepetTests/MockFlowTests.swift
import XCTest
@testable import codepet

/// The full-flow demo: `-CODEPET_MOCK_FLOW YES` must start at the cold open
/// and end in a populated company, with no network anywhere in between.
///
/// Worth testing rather than eyeballing, because both ends fail SILENTLY in
/// the same direction — a wrong `needsOnboarding` lands the founder straight
/// in the shell, and a wrong roadmap fixture leaves them in an empty one.
/// Either looks like "the demo doesn't work" with nothing saying why.
@MainActor
final class MockFlowTests: XCTestCase {

    private var previousChat: Any?
    private var previousFlow: Any?

    override func setUp() {
        super.setUp()
        previousChat = PrototypeMode.store.object(forKey: "CODEPET_MOCK_CHAT")
        previousFlow = PrototypeMode.store.object(forKey: "CODEPET_MOCK_FLOW")
        MockChat.flowOnboarded = false
        MockChat.flowBrief = nil
    }

    override func tearDown() {
        MockChat.flowBrief = nil
        restore("CODEPET_MOCK_CHAT", previousChat)
        restore("CODEPET_MOCK_FLOW", previousFlow)
        // Process-global. Left true, every later suite that reads it would see
        // a demo mid-walkthrough.
        MockChat.flowOnboarded = false
        super.tearDown()
    }

    private func restore(_ key: String, _ value: Any?) {
        if let value { PrototypeMode.store.set(value, forKey: key) }
        else { PrototypeMode.store.removeObject(forKey: key) }
    }

    // MARK: - the flag

    func testFlowImpliesMockSoOneArgumentRunsTheWholeThing() {
        // Two flags where one is meaningless without the other is a state you
        // can get half-right: mock off + flow on would run onboarding against
        // the real, dead backend.
        PrototypeMode.store.set(false, forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        XCTAssertTrue(MockChat.enabled, "flow mode did not imply mock mode")
        XCTAssertTrue(MockChat.flowEnabled)
    }

    func testPlainMockModeDoesNotStartAtOnboarding() {
        // The existing behaviour, unchanged: `-CODEPET_MOCK_CHAT` alone boots
        // an already-onboarded company, which is what makes chat and
        // engineering reachable in one launch.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(false, forKey: "CODEPET_MOCK_FLOW")
        XCTAssertTrue(MockChat.enabled)
        XCTAssertFalse(MockChat.flowEnabled)
    }

    // MARK: - the two ends of the walk

    func testTheDemoStartsBeforeOnboardingRatherThanAfterIt() {
        // `needsOnboarding` checks BOTH an absent stamp and a brief with no
        // signal. A blank brief carrying a stamp, or a stamped brief with
        // fields, would each land in the shell and skip the whole cold open.
        let fresh = MockChat.preOnboardingCompany()
        XCTAssertNil(fresh.onboardedAt)
        XCTAssertFalse(fresh.brief.hasAnySignal,
                       "the demo brief has signal, so onboarding would be skipped")
        XCTAssertTrue(fresh.tasks.isEmpty)
    }

    func testTheLoaderItselfIsWhatSendsTheDemoThroughOnboarding() async {
        // Calls `CompanyData.load` DIRECTLY rather than injecting a loader.
        //
        // Every other test here supplies its own closure, which means none of
        // them touch the branch that actually decides — deleting it left this
        // suite green. That is the same hole `EngineeringReachabilityTests`
        // exists for: correct pieces, unconnected wire. The mock path returns
        // before Firestore is touched, so this is safe to call in a test.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")

        MockChat.flowOnboarded = false
        let before = await CompanyData.load(companyId: "demo")
        XCTAssertNil(before.onboardedAt, "the demo boots past the cold open")
        XCTAssertTrue(before.tasks.isEmpty)

        MockChat.flowOnboarded = true
        let after = await CompanyData.load(companyId: "demo")
        XCTAssertNotNil(after.onboardedAt, "the demo loops back into onboarding")
        XCTAssertFalse(after.tasks.isEmpty, "the founder lands in an empty company")
    }

    func testTheRoadmapFetcherItselfAnswersFromTheFixture() async {
        // Same reasoning: `generateRoadmap` treats an empty result as "no
        // change", so a fetcher that fell through to the network would leave
        // the board empty and say nothing about why.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        var brief = CompanyBrief()
        brief.projectName = "Codepet"
        let tasks = await CompanyData.fetchRoadmap(brief: brief, language: .en)
        XCTAssertFalse(tasks.isEmpty, "the demo's board would be empty")
    }

    func testFinishingOnboardingLeavesTheDemoOnboarded() async {
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        let store = CompanyStore(loader: { _ in MockChat.preOnboardingCompany() },
                                 saver: { _, _ in true })
        await store.hydrate(companyId: "demo")
        XCTAssertTrue(store.isOnboarding, "the demo did not start at the cold open")

        var brief = CompanyBrief()
        brief.founderName = "Mona"
        brief.projectName = "Codepet"
        await store.finishOnboarding(brief: brief, token: store.onboardingToken)

        XCTAssertFalse(store.isOnboarding)
        // Without this, the next hydrate — an account switch, a sign-out —
        // drops the founder back at the cold open mid-walkthrough.
        XCTAssertTrue(MockChat.flowOnboarded)
    }

    func testSkippingCountsAsFinishing() async {
        // Otherwise Skip appears not to have worked: it leaves onboarding, and
        // the next hydrate puts them straight back into it.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        let store = CompanyStore(loader: { _ in MockChat.preOnboardingCompany() },
                                 saver: { _, _ in true })
        await store.hydrate(companyId: "demo")

        await store.skipOnboarding()

        XCTAssertFalse(store.isOnboarding)
        XCTAssertTrue(MockChat.flowOnboarded)
    }

    // MARK: - what the founder lands in

    func testTheFakeCompanyHasWorkCodepetCanActuallyRun() {
        // The roadmap fixture is the whole point of landing in a company: an
        // empty board makes every downstream surface — chat's runnable list,
        // the fan-out, the Tasks page — demo as if broken.
        let tasks = MockChat.roadmap()
        XCTAssertFalse(tasks.isEmpty)
        let depts = Set(tasks.filter { $0.who == .draft && $0.phase == .find }.map { $0.dept })
        XCTAssertGreaterThanOrEqual(depts.count, 3,
            "fewer than three departments have runnable work, so the fan-out demos as one agent")
    }

    // MARK: - whose project is this

    func testTheDemoKeepsTheProjectTheFounderTyped() async {
        // The bug this closes: `CompanyData.load` answers every hydrate after
        // onboarding with `company()`, whose brief was hardcoded — so a
        // founder who onboarded something else watched their project silently
        // become Codepet on the next account switch.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        let store = CompanyStore(loader: { _ in MockChat.preOnboardingCompany() },
                                 saver: { _, _ in true })
        await store.hydrate(companyId: "demo")

        var brief = CompanyBrief()
        brief.founderName = "Mona"
        brief.projectName = "Murror"
        await store.finishOnboarding(brief: brief, token: store.onboardingToken)

        let reloaded = await CompanyData.load(companyId: "demo")
        XCTAssertEqual(reloaded.brief.projectName, "Murror",
                       "the demo replaced the founder's project with the fixture's")
    }

    func testCannedCopyNamesTheFoundersProductNotOurs() {
        // Thirteen hardcoded mentions used to say "Codepet" no matter what was
        // onboarded, which reads as the fixture having ignored what they typed.
        var brief = CompanyBrief()
        brief.projectName = "Murror"
        MockChat.flowBrief = brief

        let filled = MockChat.fill("Here's where {{product}} stands.")
        XCTAssertEqual(filled, "Here's where Murror stands.")
        XCTAssertFalse(filled.contains("{{"), "a token leaked into copy the founder reads")
    }

    func testWithNoFlowBriefTheCopyStillNamesSomething() {
        // Plain `-CODEPET_MOCK_CHAT` never captures a brief. The token must
        // still resolve — a raw `{{product}}` on screen is worse than a name
        // that happens to be ours.
        MockChat.flowBrief = nil
        XCTAssertEqual(MockChat.fill("{{product}} ships."), "Codepet ships.")
    }

    func testABlankProjectNameDoesNotProduceAnEmptySentence() {
        var brief = CompanyBrief()
        brief.projectName = "   "
        MockChat.flowBrief = brief
        XCTAssertEqual(MockChat.fill("{{product}} ships."), "Codepet ships.")
    }

    // MARK: - enrichment

    func testEnrichmentFillsTheBlanksAndKeepsWhatWasTyped() {
        // A mock that overwrote the founder's own words would show them
        // someone else's project at the reveal — the moment the whole
        // onboarding gets judged on.
        var brief = CompanyBrief()
        brief.projectName = "Codepet"
        brief.oneLiner = "My own sentence."
        let enriched = MockChat.enrich(brief)

        XCTAssertEqual(enriched.oneLiner, "My own sentence.")
        XCTAssertFalse((enriched.audience ?? "").isEmpty, "a blank field was left blank")
        XCTAssertFalse((enriched.goal ?? "").isEmpty)
    }

    func testEnrichmentTreatsWhitespaceAsEmpty() {
        // A founder who tabbed through and one who typed spaces both left it
        // empty; the real enricher fills both.
        var brief = CompanyBrief()
        brief.projectName = "Codepet"
        brief.oneLiner = "   "
        let enriched = MockChat.enrich(brief)
        XCTAssertTrue((enriched.oneLiner ?? "").contains("Codepet"),
                      "a whitespace-only sentence was treated as written")
    }

    func testEnrichmentNamesTheProjectTheFounderTyped() {
        var brief = CompanyBrief()
        brief.projectName = "Murror"
        let enriched = MockChat.enrich(brief)
        XCTAssertTrue((enriched.oneLiner ?? "").contains("Murror"),
                      "the reveal would show a project the founder never named")
    }

    // MARK: - the approve beat waits for its draft

    /// **The bug this guards.** `.approveNewestDraft` used to check for a draft exactly
    /// once, at the moment its OWN timer fired, and silently return if the run beat
    /// before it hadn't produced one yet — a race against Reduce Motion (every beat
    /// capped at 0.8s), a Brisk pace below 1.0 (both of which shrink the SCRIPT's
    /// margin), and `CODEPET_SLOW_RUNS` (2-20x the run's OWN step timing, which the
    /// player's pace does not touch at all). Losing it meant the beat filed nothing:
    /// the predecessor task stayed `drafted` forever and the library never grew.
    ///
    /// **Why the injected delay has to outlast the WHOLE remaining script, not just
    /// one beat's gap.** The first miss is not the end of the story: every later
    /// `.runTask` in the day-one chain depends (directly or transitively) on
    /// `mur-landscape`, and `offerChainIfNeeded` blocks a run whose dependency has no
    /// FILED deliverable yet — regardless of `done` — so as long as `mur-landscape`
    /// stays unfiled, every later run becomes a harmless chain-offer card instead of a
    /// competing draft. That leaves `mur-landscape`'s draft the ONLY one in play, which
    /// means a LATER `.approveNewestDraft` beat can still stumble onto it once it's
    /// ready — an early version of this test used a 1.5s delay against a ~0.3-0.5s
    /// per-beat gap and passed even against the unfixed handler, because the SECOND
    /// approve beat happened to land after the draft turned up. That was not the fix
    /// working; it was luck at a several-hundred-millisecond margin. Making the delay
    /// (20s) outlast the entire script's real playback (≈10s at this pace; ≤16.8s even
    /// under Reduce Motion, where every beat caps at 0.8s) means NO approve beat —
    /// first, second, or last — can find the draft under the unfixed handler, so a
    /// failure here is the real bug and not a coin flip.
    ///
    /// Reproduced without touching either script's authored `seconds` (the founder's
    /// rule): a very low `pace` shrinks the script's OWN real playback time, and the
    /// injected `taskRunner`'s 20s sleep outlasts it — the same shape `CODEPET_SLOW_RUNS`
    /// produces at full scale (up to ≈55.6s beyond a normal run), just scaled down so
    /// this test runs in well under a minute instead of several. `CompanyStore.
    /// execStepNanos`/`execDoneBeatNanos` are zeroed (the documented "tests set it to 0"
    /// seam) so the injected sleep is the ONLY source of delay in the run itself.
    func testApproveBeatFilesTheDraftEvenWhenTheRunIsStillSlowerThanTheBeat() async throws {
        // The day-one script is what uses `.runTask(id)` rather than `.runBeacon`, so
        // the run's target task is named in the script instead of resolved through
        // `RoadmapEngine.nextStep` — this test needs to know exactly which task the
        // slow `taskRunner` below has to stall.
        let previousProject = PrototypeMode.store.string(forKey: DemoProject.key)
        defer {
            if let previousProject { PrototypeMode.store.set(previousProject, forKey: DemoProject.key) }
            else { PrototypeMode.store.removeObject(forKey: DemoProject.key) }
        }
        DemoProject.select("murror-day-one")

        let previousStepNanos = CompanyStore.execStepNanos
        let previousDoneBeatNanos = CompanyStore.execDoneBeatNanos
        defer {
            CompanyStore.execStepNanos = previousStepNanos
            CompanyStore.execDoneBeatNanos = previousDoneBeatNanos
        }
        CompanyStore.execStepNanos = 0
        CompanyStore.execDoneBeatNanos = 0

        let project = DemoProject.murrorDayOne
        let seed = CompanyState(brief: project.brief, departments: [], library: project.library(),
                                stage: .building, companionId: "byte", onboardedAt: Date(),
                                tasks: project.tasks)
        let store = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in true },
            // The script's `.walkthroughFounderTask` beat (ahead of the run/approve pair
            // this test cares about) calls `sendChat`, which without these would reach
            // the REAL transport — `MockChat.stream`/`reply` keep it offline, same as
            // every other mock-mode surface.
            chatSender: { await MockChat.reply($0) },
            chatStreamer: { MockChat.stream($0) },
            // 20s: comfortably longer than the day-one script's own real playback at
            // ANY pace/Reduce-Motion combination (see the doc comment above) — every
            // `.approveNewestDraft` beat in the script, not just the first, must find
            // nothing until this fires, or the test proves nothing.
            taskRunner: { req in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                let entry = project.deliverable(for: req.taskTitle)
                return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                                       body: MockChat.fill(entry.body, title: req.taskTitle))
            },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
        await store.hydrate(companyId: "u")

        let player = MockFlowPlayer()
        player.attach(store: store, language: .en)
        // Brisk-below-1.0, several times over — one of the three real races named
        // above. Shrinks the script's own ~65s authored total to a real playback of
        // well under the 20s the injected `taskRunner` sleeps.
        player.pace = 0.15

        // Playing from the top walks the whole day-one script — every run/approve
        // pair after "mur-landscape" degrades to a harmless chain-offer (see the doc
        // comment above), so this reaches the same end state a `jump` to any single
        // pair would, without needing to set `index`, which the player exposes no
        // setter for.
        player.play()

        // 40s: past the ~20s the draft needs plus the script's own real playback, with
        // margin. Under the unfixed handler this loop runs out the full 40s and the
        // assertions below fail — that is the point of this test.
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if store.company.tasks.first(where: { $0.id == "mur-landscape" })?.done == true { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(store.company.tasks.first(where: { $0.id == "mur-landscape" })?.done, true,
                       "the approve beat(s) fired before the run's draft existed, and filed nothing")
        XCTAssertTrue(store.company.library.contains { $0.sourceTaskId == "mur-landscape" },
                      "approved but never actually filed to the library")
    }

    // MARK: - a `.runTask` beat waits for its own run to resolve

    /// **The bug this guards.** `MockFlowPlayer` fired `Task { await store.runTask(...) }` for a
    /// `.runTask` beat and let its OWN timer advance the player on the beat's authored `seconds`
    /// regardless of whether that run had actually finished. In mock mode a run resolves in
    /// ~2.5s against a ~2.6s beat, so this never showed; under `CODEPET_LIVE_AI` a real run takes
    /// 20-60s, and the player kept walking through several more departments' beats — posting
    /// their `asks`/`frames` lines into the SAME transcript — while the earlier run was still in
    /// flight. When that run finally resolved, its draft (and the approval that follows it)
    /// landed underneath whatever department's message was on screen by then: the founder's own
    /// screenshot, a Sales artifact ("Who Murror Is Not For — Sales Disqualifiers") appearing
    /// under Support · Sage's message.
    ///
    /// **Why this is a DIFFERENT bug than the one `testApproveBeatFilesTheDraftEvenWhenTheRunIs
    /// StillSlowerThanTheBeat` above guards.** That test's `.approveNewestDraft` wait already
    /// makes the draft get approved and filed correctly no matter how late it arrives — the
    /// deliverable is never lost. This bug is about WHERE it lands: the player must not walk
    /// through later departments' chat lines while an earlier department's run is still pending,
    /// even though that earlier run's draft will eventually be approved just fine. So the signal
    /// this test checks is not "did it get filed" (already covered) but "did the NEXT department
    /// speak before this run resolved" — Sales · Nova's `asks` line must not appear in the
    /// transcript while `mur-landscape`'s run (Marketing · Nova, the day-one chain's first
    /// `.runTask`) is still in `runningTaskIds`.
    ///
    /// **Reproduced the same way the sibling test above does**: a very low `pace` shrinks the
    /// script's own real playback far below the injected `taskRunner`'s artificial delay (1.8s
    /// here — long enough to leave a wide, reliable window; short enough to keep this test fast),
    /// which is the same shape `CODEPET_LIVE_AI`'s real 20-60s produces against a live beat, just
    /// scaled down. `execStepNanos`/`execDoneBeatNanos` are zeroed so the injected sleep is the
    /// only source of delay in the run itself.
    ///
    /// Verified red by hand: reverting `MockFlowPlayer.step()`/`schedule(after:)` to the
    /// fire-and-forget shape (`Task { await store.runTask(...) }` inside `perform()`, with
    /// `step()` scheduling the next beat unconditionally) makes this fail — the low pace races
    /// the player straight through Marketing's report and Sales' opening while `mur-landscape` is
    /// still running.
    /// **The run beat must not advance until its own run resolves.**
    ///
    /// Rewritten 7 Sep after it failed in CI. It used to depend on three wall-clock windows
    /// lining up — a 0.05 pace, an injected 1.8s sleep, and a 2.2s wait — and its own guard
    /// ("the run should still be in flight at this point") is what tripped: on CI's timing the
    /// run had already finished before the assertion looked. A test that only proves something
    /// when the machine is the right speed proves nothing on any other machine.
    ///
    /// The runner now blocks until this test releases it, so the window is controlled rather
    /// than hoped for, and every wait polls a condition instead of sleeping a guessed duration.
    func testARunTaskBeatDoesNotAdvanceUntilItsOwnRunResolves() async throws {
        let previousStepNanos = CompanyStore.execStepNanos
        let previousDoneBeatNanos = CompanyStore.execDoneBeatNanos
        defer {
            CompanyStore.execStepNanos = previousStepNanos
            CompanyStore.execDoneBeatNanos = previousDoneBeatNanos
        }
        CompanyStore.execStepNanos = 0
        CompanyStore.execDoneBeatNanos = 0

        // The gate the RUN waits on. `@unchecked Sendable` over a lock rather than an actor:
        // the runner closure is non-isolated and the player is `@MainActor`, and a plain flag
        // keeps the test readable without hopping actors to read one Bool.
        final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var open = false
            var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
            func release() { lock.lock(); open = true; lock.unlock() }
        }
        let gate = Gate()

        let project = DemoProject.murrorDayOne
        let seed = CompanyState(brief: project.brief, departments: [], library: project.library(),
                                stage: .building, companionId: "byte", onboardedAt: Date(),
                                tasks: project.tasks)
        let store = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in true },
            chatSender: { await MockChat.reply($0) },
            chatStreamer: { MockChat.stream($0) },
            taskRunner: { req in
                // Held open until the test says so — this is what makes the window exact.
                while !gate.isOpen { try? await Task.sleep(nanoseconds: 5_000_000) }
                let entry = project.deliverable(for: req.taskTitle)
                return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                                       body: MockChat.fill(entry.body, title: req.taskTitle))
            },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
        await store.hydrate(companyId: "u")

        // **Select the day-one project, or this test proves nothing.**
        // `MockFlowPlayer` picks its script from `DemoProject.current.id == "murror-day-one"`,
        // and under XCTest `PrototypeMode.store` is a scratch suite with nothing set — so
        // `current` falls back to `.codepet` and the player loads the 24-beat TOUR. The
        // assertion below ("Sales · Nova's ask has not appeared") is then trivially true,
        // because that chapter does not exist in the tour. This test passed vacuously until
        // CI's timing tripped its own in-flight guard and exposed it.
        DemoProject.select("murror-day-one")
        defer { DemoProject.select("codepet") }

        let player = MockFlowPlayer()
        player.attach(store: store, language: .en)
        XCTAssertTrue(player.beats.count > 24,
                      "the player loaded the 24-beat tour, not the day-one script — every "
                      + "assertion below would pass without proving anything")
        // Shrinks the authored beats so the script's own pacing cannot be what holds the player
        // back — only the fix, or its absence, can.
        player.pace = 0.05
        player.play()

        /// Polls a condition instead of sleeping a guessed duration. Returns false on timeout,
        /// so a hang fails with the assertion's own message rather than as a stalled suite.
        func waitUntil(_ timeout: TimeInterval = 5, _ cond: @MainActor () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if cond() { return true }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return cond()
        }

        let started = await waitUntil(15) { store.runningTaskIds.contains("mur-landscape") }
        XCTAssertTrue(started,
                      "mur-landscape's run never started — player at beat \(player.index) of "
                      + "\(player.beats.count), \(store.chatMessages.count) messages posted")

        // The run is now DEFINITELY in flight: it cannot finish until `gate.release()` below.
        // Under the unfixed handler the player would already have raced into the next chapter.
        let salesAsk = DayOneScript.line(for: "sales", .asks, language: .en)
        XCTAssertFalse(store.chatMessages.contains { $0.text == salesAsk },
                      "the player advanced into Sales · Nova's chapter while mur-landscape's run "
                      + "was still in flight — a `.runTask` beat must not advance until its own "
                      + "run resolves")

        // And it must not stall forever either: once the run resolves, the script moves on.
        gate.release()
        let resumed = await waitUntil { !store.runningTaskIds.contains("mur-landscape") }
        XCTAssertTrue(resumed, "the run never resolved after the gate opened")

        player.pause()
    }
}
