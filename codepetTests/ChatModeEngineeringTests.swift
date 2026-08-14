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
        previousMockFlag = UserDefaults.standard.object(forKey: "CODEPET_MOCK_CHAT")
        UserDefaults.standard.set(true, forKey: "CODEPET_MOCK_CHAT")
    }

    override func tearDown() {
        if let previousMockFlag {
            UserDefaults.standard.set(previousMockFlag, forKey: "CODEPET_MOCK_CHAT")
        } else {
            UserDefaults.standard.removeObject(forKey: "CODEPET_MOCK_CHAT")
        }
        super.tearDown()
    }

    private func makeStore() -> CompanyStore {
        let state = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                 stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
        return CompanyStore(loader: { _ in state }, saver: { _, _ in true })
    }

    func testBuildGoesToTheCloudAgent() {
        // Cloud is the default because it is the one that works for a customer:
        // the local runner shells out to the `claude` CLI, which nobody who
        // downloads Codepet has. Defaulting to local would ship a mode that
        // does nothing for anyone but us.
        let store = makeStore()
        store.startBuild(ask: "add stripe checkout")
        XCTAssertNotNil(store.engineeringRunStore, "Build did not start a cloud run")
        XCTAssertNil(store.codingRun.run, "Build silently started the LOCAL agent")
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
        let store = makeStore()
        store.startBuild(ask: "add stripe checkout")
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
