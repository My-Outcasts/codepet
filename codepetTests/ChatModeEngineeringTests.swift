// codepetTests/ChatModeEngineeringTests.swift
import XCTest
@testable import codepet

/// Three modes. `ChatComposer` renders `ChatMode.composerCases`, so the picker
/// changes with no view edit — which also means a mistake here reaches the
/// founder's composer with nothing in between.
///
/// There were four until 14 Aug. Ask and Plan are a real choice about intent;
/// Build and "Developer" were not a choice about anything the founder wanted,
/// only about which machine ran it.
final class ChatModeEngineeringTests: XCTestCase {

    func testThereAreThreeModesAndBuildIsTheCodeOne() {
        XCTAssertEqual(ChatMode.allCases.count, 3)
        XCTAssertEqual(ChatMode.allCases, [.ask, .plan, .build])
    }

    func testTheComposerOffersEveryModeThatGoesSomewhere() {
        // The rule this pins outlives its contents: a mode belongs in the
        // picker only once its send has a destination. `.engineering` was held
        // OUT of this list for two plans while its send did nothing.
        XCTAssertEqual(Set(ChatMode.composerCases), Set(ChatMode.allCases),
                       "a mode with a working send is missing from the composer")
    }

    func testNoModeIsCalledDeveloperAnyMore() {
        // The word survived one rename already — Engineering → Developer, to
        // break a collision with the department chip — and the real answer was
        // that the mode should not exist. If it comes back, the collision
        // question comes back with it.
        for mode in ChatMode.composerCases {
            for lang: AppLanguage in [.en, .vi] {
                XCTAssertNotEqual(mode.label(lang).lowercased(), "developer")
                XCTAssertNotEqual(mode.label(lang).lowercased(), "engineering")
            }
        }
    }

    func testBuildDoesNotConveneTheRoom() {
        // A room DELIBERATES; Build EXECUTES. Convening would also add ~$0.20
        // per message to a mode that already spends real money on a run —
        // against ~$0.005 for an ordinary turn.
        XCTAssertFalse(ChatMode.build.convenesRoom)
    }

    func testOnlyPlanStillConvenesTheRoom() {
        // Guards the invariant rather than a case: removing a mode must not
        // widen what fans out to virtualCompanyRun, and neither must adding one.
        XCTAssertEqual(ChatMode.allCases.filter(\.convenesRoom), [.plan])
    }

    func testBuildSendsTheFoundersTextUnchanged() {
        // Changed with the merge. Build's text now becomes `engStartRun`'s
        // `ask` — the agent's actual instruction AND the session title a
        // founder scans a list of runs by — so framing copy would land in both.
        // Build's old wrapper ("Let's build this together…") was already dead:
        // `send()` routed `.build` straight to a runner and never called shape.
        let ask = "add stripe checkout"
        XCTAssertEqual(ChatMode.build.shape(ask, language: .en), ask)
        XCTAssertEqual(ChatMode.build.shape(ask, language: .vi), ask)
    }

    func testTheTalkingModesStillWrapTheirText() {
        // The regression this catches: making Build identity by making `shape`
        // identity for everything.
        let text = "price the beta"
        XCTAssertNotEqual(ChatMode.plan.shape(text, language: .en), text)
        XCTAssertEqual(ChatMode.ask.shape(text, language: .en), text, "ask has always been identity")
    }

    func testEveryModeHasALabelInBothLanguages() {
        for mode in ChatMode.allCases {
            XCTAssertFalse(mode.label(.en).isEmpty, "\(mode) has no English label")
            XCTAssertFalse(mode.label(.vi).isEmpty, "\(mode) has no Vietnamese label")
            XCTAssertNotEqual(mode.label(.en), mode.label(.vi),
                              "\(mode) shows English to a Vietnamese founder")
        }
    }

    func testNoModeLabelCollidesWithADepartmentName() {
        // The bug Mona found by looking at the composer: the picker said
        // "Engineering" eight points below a department chip that also said
        // "Engineering", and behind the two words were two different coding
        // agents. Merging the modes removed the second agent from the picker;
        // this keeps the words apart if a mode is ever added back.
        for mode in ChatMode.composerCases {
            for dept in DepartmentCatalog.all {
                for lang: AppLanguage in [.en, .vi] {
                    XCTAssertNotEqual(
                        mode.label(lang).lowercased(), dept.name.lowercased(),
                        "the \(mode) mode and the \(dept.key) department are both called "
                        + "\"\(dept.name)\" in \(lang) — they sit in the same composer"
                    )
                }
            }
        }
    }
}

/// Where a Build actually runs, and whether the founder can tell.
@MainActor
final class BuildDestinationTests: XCTestCase {

    private var previousMockFlag: Any?

    override func setUp() {
        super.setUp()
        // `startBuild` reaches the real `EngineeringClient` without this, and
        // `Auth.auth()` TRAPS on unconfigured Firebase (landmine #4) from a
        // detached Task, after the test has already passed.
        previousMockFlag = PrototypeMode.store.object(forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_CHAT")
    }

    override func tearDown() {
        if let previousMockFlag {
            PrototypeMode.store.set(previousMockFlag, forKey: "CODEPET_MOCK_CHAT")
        } else {
            PrototypeMode.store.removeObject(forKey: "CODEPET_MOCK_CHAT")
        }
        super.tearDown()
    }

    private func makeStore() -> CompanyStore {
        let state = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                 stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
        // This class never hydrates, so `account` stays nil and `linkProject`'s bind is a
        // no-op regardless — but an injected suite (the `CompanyStoreProjectIdentityTests
        // .makeStore` pattern) keeps that safe rather than lucky if a future test adds a
        // hydrate call.
        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        return CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                            identityMap: ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test"))
    }

    /// Was `testBuildGoesToTheCloudAgent`, which asserted the exact opposite: with nothing
    /// linked, Build started the cloud coding agent. That agent runs on `engStartRun`, which
    /// declares `ANTHROPIC_API_KEY` and has answered 401 since the key was deleted on
    /// 26 Aug 2026 — so the old default was not "the one that works for a customer" any more,
    /// it was a network error with no explanation. `.noProject` is the same refusal the local
    /// runner already gives, and its card carries the button that fixes it.
    func testBuildWithNoFolderLinkedAsksForOneInsteadOfTheCloud() {
        let store = makeStore()
        store.startBuild(ask: "add stripe checkout")
        XCTAssertEqual(store.codingRun.run?.phase, .noProject,
                       "Build with nothing linked did not stage the Link-a-project card")
        XCTAssertNil(store.engineeringRunStore, "Build still dispatched to the cloud coding agent")
    }

    func testBuildStaysInTheCloudEVENWHENAFolderIsLinked() {
        // The guard that matters, and the one the no-project test cannot see:
        // with local available, "route to whichever is set up" and "always
        // cloud" behave identically until a folder exists. A mutation that
        // preferred local passed the other test cleanly.
        //
        // Preferring local here would be the silent routing this merge exists
        // to prevent — same button, different machine, different bill, nothing
        // on screen saying which.
        let store = makeStore()
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)
        XCTAssertTrue(store.localBuildAvailable, "the fixture failed to link a folder")

        store.startBuild(ask: "add stripe checkout")

        XCTAssertNotNil(store.engineeringRunStore, "Build chose the local agent because a folder existed")
        XCTAssertNil(store.codingRun.run, "Build silently started the LOCAL agent")
    }

    /// The grant flips the default. A founder who said "Codepet may spend my Claude plan"
    /// and linked a folder gets their OWN agent, because the cloud one spends the Anthropic
    /// key that grant exists to stop spending — and `CloudAIBlock` may be refusing
    /// `engStartRun` outright, which would fail as an unexplained network error.
    func testAGrantedFounderWithAFolderGetsTheirOwnAgent() async {
        let store = grantedStore()
        await store.hydrate(companyId: "c1")
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)
        XCTAssertTrue(store.buildRunsOnFoundersAgent, "the fixture failed to grant + link")

        store.startBuild(ask: "add stripe checkout")

        XCTAssertNotNil(store.codingRun.run, "a granted Build did not run on the founder's agent")
        XCTAssertNil(store.engineeringRunStore, "a granted Build still spent the API key")
    }

    /// A grant is not a folder — but the answer to "no folder" is now to ask for one, not to
    /// send the run to an agent that cannot answer. This case asserted the cloud dispatch
    /// before; `.noProject` is where both halves of that sentence now land.
    func testAGrantWithNoFolderStillAsksForAFolder() async {
        let store = grantedStore()
        await store.hydrate(companyId: "c1")
        XCTAssertFalse(store.buildRunsOnFoundersAgent, "the fixture linked a folder by accident")

        store.startBuild(ask: "add stripe checkout")

        XCTAssertEqual(store.codingRun.run?.phase, .noProject)
        XCTAssertNil(store.engineeringRunStore, "a granted founder was sent to the cloud agent")
    }

    /// The grant is per company id — one Mac has one Claude Code login, so founder A's
    /// consent must not route founder B's Build onto the plan A signed in with.
    func testAnotherFoundersGrantDoesNotMoveThisBuild() async {
        let store = grantedStore(granted: "someone-else")
        await store.hydrate(companyId: "c1")
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)

        store.startBuild(ask: "add stripe checkout")

        XCTAssertNotNil(store.engineeringRunStore)
        XCTAssertNil(store.codingRun.run)
    }

    /// A grant table in memory, so no case here touches the real defaults domain: a leaked
    /// grant would move another suite's Build to a machine it never asked for.
    private func grantedStore(granted: String = "c1") -> CompanyStore {
        let state = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                 stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        return CompanyStore(
            loader: { _ in state }, saver: { _, _ in true },
            identityMap: ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test"),
            claudeAuthorisation: ProviderAuthorisation(
                isAuthorised: { $1 == granted }, setAuthorised: { _, _, _ in }))
    }

    /// The one state that still reaches the cloud coding agent: a folder IS linked and the
    /// founder has NOT granted her Claude plan. `engStartRun` 401s today, so before that
    /// dispatch fires the founder must see why the build cannot run and how to fix it —
    /// `BlockReason.notGranted`'s own copy, not a new sentence.
    func testBuildWithAFolderButNoGrantNoticesTheFounderBeforeTheCloudRun() {
        let store = makeStore()
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)

        store.startBuild(ask: "add stripe checkout")

        XCTAssertTrue(
            store.chatMessages.contains { $0.role == .companion && $0.text == BlockReason.notGranted.founderText },
            "an ungranted, folder-linked Build did not tell the founder why it cannot run"
        )
        // The branch itself is unchanged: it still reaches the cloud agent (Task 7's onboarding
        // gate is what stops that dispatch, not this notice).
        XCTAssertNotNil(store.engineeringRunStore)
        XCTAssertNil(store.codingRun.run)
    }

    /// Same case in Vietnamese — the recorded defect here is a ternary that returns the SAME
    /// string on both branches (`lang == .vi ? why : why`), so an English-only assertion would
    /// pass even if `.vi` silently got English copy.
    func testBuildWithAFolderButNoGrantNoticesInVietnamese() {
        let store = makeStore()
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)

        store.startBuild(ask: "add stripe checkout", language: .vi)

        XCTAssertTrue(
            store.chatMessages.contains { $0.role == .companion && $0.text == BlockReason.notGranted.founderTextVi },
            "the Vietnamese founder was not shown the Vietnamese notice"
        )
        XCTAssertFalse(
            store.chatMessages.contains { $0.role == .companion && $0.text == BlockReason.notGranted.founderText },
            "the Vietnamese founder was shown the English notice instead"
        )
    }

    func testTheSwitchActuallyMovesTheRunToTheOtherMachine() {
        // And drops the cloud one: two coding agents on one ask, writing to two
        // different places, is a state no card could explain.
        let store = makeStore()
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)
        store.startBuild(ask: "add stripe checkout")

        store.switchBuildToLocal(ask: "add stripe checkout")

        XCTAssertNotNil(store.codingRun.run, "the switch did not start a local run")
        XCTAssertNil(store.engineeringRunStore, "both agents are now running the same ask")
        XCTAssertEqual(store.chatMessages.filter { $0.text == "add stripe checkout" }.count, 1,
                       "the founder reads their own sentence twice")
    }

    func testWithNoProjectLinkedThereIsNoLocalOfferToMake() {
        // An offer to run somewhere the founder has not set up is not an offer.
        let store = makeStore()
        XCTAssertFalse(store.localBuildAvailable)
    }

    func testSwitchingWithNoProjectLinkedChangesNothing() {
        // The control is hidden in this state; this is the guard behind it, so
        // a stale closure cannot start a run against a folder that is not there.
        //
        // The precondition is built with `startEngineeringRun` directly because no Build
        // entry point reaches the cloud agent with nothing linked any more — that is this
        // task's whole change. The assertions are unchanged: the guard, not the route, is
        // what this case has always protected.
        let store = makeStore()
        store.startEngineeringRun(ask: "add stripe checkout")
        store.switchBuildToLocal(ask: "add stripe checkout")
        XCTAssertNotNil(store.engineeringRunStore, "the cloud run was dropped for nothing")
        XCTAssertNil(store.codingRun.run)
    }

    func testTheSwitchIsOfferedOnlyBeforeThereIsAnythingToLose() {
        // Once a run is reviewing or paused it has produced a branch, and
        // "run on my machine" reads as "also do this" rather than "abandon
        // that". Early on there is nothing to abandon.
        XCTAssertTrue(EngineeringResultBar.canSwitchToLocal(.preparing))
        XCTAssertTrue(EngineeringResultBar.canSwitchToLocal(.running))
        XCTAssertTrue(EngineeringResultBar.canSwitchToLocal(.awaitingApproval))
        XCTAssertFalse(EngineeringResultBar.canSwitchToLocal(.reviewing))
        XCTAssertFalse(EngineeringResultBar.canSwitchToLocal(.budgetReached))
        XCTAssertFalse(EngineeringResultBar.canSwitchToLocal(.failed("x")))
    }
}

/// The OTHER Build entry point: a two-mode Developer session (`DeveloperWorkPane`).
///
/// It had the same shape as `startBuild` — linked folder → local, nothing linked → the cloud
/// coding agent — and `CLAUDE.md` recorded it as "the only call left that can reach the cloud
/// agent by design". That design rested on the cloud agent being able to answer. It cannot:
/// `engStartRun` spends the Anthropic key deleted on 26 Aug 2026 and 401s.
@MainActor
final class SessionBuildDestinationTests: XCTestCase {

    private var previousMockFlag: Any?

    override func setUp() {
        super.setUp()
        // Same reason as `BuildDestinationTests`: without the flag a cloud run builds a real
        // `EngineeringClient`, which reaches `Auth.auth()` and TRAPS on unconfigured Firebase
        // (landmine #4) from a detached Task, after the test has already passed.
        previousMockFlag = PrototypeMode.store.object(forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_CHAT")
    }

    override func tearDown() {
        if let previousMockFlag {
            PrototypeMode.store.set(previousMockFlag, forKey: "CODEPET_MOCK_CHAT")
        } else {
            PrototypeMode.store.removeObject(forKey: "CODEPET_MOCK_CHAT")
        }
        super.tearDown()
    }

    private func makeStore() -> CompanyStore {
        let state = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                 stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        return CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                            identityMap: ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test"))
    }

    func testASessionBuildWithNoFolderAsksForOneInsteadOfTheCloud() {
        let store = makeStore()
        store.startSessionBuild(ask: "add stripe checkout")
        XCTAssertEqual(store.codingRun.run?.phase, .noProject,
                       "a session Build with nothing linked did not stage the no-project card")
        XCTAssertNil(store.engineeringRunStore,
                     "a session Build still dispatched to the cloud coding agent")
    }

    /// The regression that would silently disable local builds. Routing the no-folder branch
    /// must not route the WITH-folder one: a linked project still reaches `startCodeRun`, and
    /// a run that stages `.noProject` with a folder present is a Developer pane that can never
    /// run anything.
    func testASessionBuildWithAFolderStillRunsOnTheFoundersMachine() {
        let store = makeStore()
        _ = store.linkProject(path: NSTemporaryDirectory(), bootstrapClaudeMd: false)

        store.startSessionBuild(ask: "add stripe checkout")

        XCTAssertNotNil(store.codingRun.run, "a linked session Build staged no local run at all")
        XCTAssertNotEqual(store.codingRun.run?.phase, .noProject,
                          "a linked session Build was told there is no project")
        XCTAssertNil(store.engineeringRunStore)
        XCTAssertEqual(store.codingRun.run?.ask, "add stripe checkout")
    }

    /// The ask reaches the transcript either way — a refusal the founder cannot see their own
    /// sentence next to is the dead end `.noProject` exists to avoid.
    func testTheAskIsStillEchoedWhenThereIsNoFolder() {
        let store = makeStore()
        store.startSessionBuild(ask: "add stripe checkout")
        XCTAssertEqual(store.chatMessages.map(\.text), ["add stripe checkout"])
        XCTAssertEqual(store.codingRun.run?.ask, "add stripe checkout")
    }

    func testABlankSessionBuildStartsNothing() {
        let store = makeStore()
        store.startSessionBuild(ask: "   ")
        XCTAssertNil(store.codingRun.run)
        XCTAssertNil(store.engineeringRunStore)
        XCTAssertTrue(store.chatMessages.isEmpty)
    }
}
