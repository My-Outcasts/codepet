// codepetTests/FounderPrefsPersistenceTests.swift
import XCTest
@testable import codepet

@MainActor
final class FounderPrefsPersistenceTests: XCTestCase {
    func test_setFounderPrefs_updatesStateAndWritesOnce() async {
        var written: [FounderPrefs] = []
        let store = CompanyStore(loader: { _ in .empty },
                                 founderPrefsSaver: { _, prefs in
            written.append(prefs); return true
        })
        // A company id is what makes the write addressable — same precondition as
        // `setCompanion`/`setFounderName`, so hydrate an account first.
        await store.hydrate(companyId: "u")
        var prefs = FounderPrefs()
        prefs.style.baseTone = .direct
        await store.setFounderPrefs(prefs)

        XCTAssertEqual(store.company.founderPrefs.style.baseTone, .direct)
        XCTAssertEqual(written.count, 1)
    }

    func test_defaultPrefsSurviveDecodingACompanyWithoutTheField() throws {
        // Existing company docs predate founderPrefs; decoding must not throw.
        let json = #"{"brief":{},"departments":[],"companionId":"crash","tasks":[],"enabledTools":[]}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertEqual(state.founderPrefs, FounderPrefs())
    }

    /// A stored `founderPrefs` object must survive the round trip, and a partially
    /// written one must fill the rest in from the defaults (the Task 7 decoder).
    func test_storedPrefsDecodeOntoTheCompany() throws {
        let json = #"""
        {"brief":{},"departments":[],"companionId":"byte","tasks":[],"enabledTools":[],
         "founderPrefs":{"memoryEnabled":false,"style":{"baseTone":"encouraging"}}}
        """#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertFalse(state.founderPrefs.memoryEnabled)
        XCTAssertEqual(state.founderPrefs.style.baseTone, .encouraging)
        XCTAssertEqual(state.founderPrefs.style.warmth, .default)   // absent key → declared default
        XCTAssertEqual(state.founderPrefs.notifications, [:])
    }

    /// The read side of the sync: a doc that carries `founderPrefs` must reach
    /// `CompanyState` through `CompanyData.state(from:)`, and a doc that doesn't must
    /// land on the defaults rather than throwing.
    func test_companyDataMapsFounderPrefsFromTheDoc() throws {
        let payload = CompanyData.founderPrefsPayload({
            var p = FounderPrefs()
            p.style.baseTone = .analytical
            p.memoryEnabled = false
            p.notifications = ["deliverables": .inApp]
            return p
        }())
        let data = try JSONSerialization.data(withJSONObject: payload)
        let doc = try JSONDecoder().decode(CompanyDoc.self, from: data)
        let state = CompanyData.state(from: doc)
        XCTAssertEqual(state.founderPrefs.style.baseTone, .analytical)
        XCTAssertFalse(state.founderPrefs.memoryEnabled)
        XCTAssertEqual(state.founderPrefs.notifications, ["deliverables": .inApp])

        // No field on the doc → defaults, never a throw.
        XCTAssertEqual(CompanyData.state(from: CompanyDoc()).founderPrefs, FounderPrefs())
    }

    /// Regression, same hazard as `setFounderName`: `hydrate` flips `companyId` to the
    /// INCOMING account BEFORE `company` loads for it, so a prefs write enqueued in that
    /// window (a settings panel committing a draft from inside a sign-out / account
    /// switch) must not land on the incoming account's document.
    func test_setFounderPrefsDroppedWhileHydratingADifferentAccount() async {
        let loaderEntered = OneShotGate()
        let letLoaderFinish = OneShotGate()
        var writes: [(cid: String, prefs: FounderPrefs)] = []

        let bState = CompanyState(brief: CompanyBrief(projectName: "B-Co"),
                                  departments: [], library: [], stage: .growth,
                                  companionId: "byte", onboardedAt: Date())

        let store = CompanyStore(
            loader: { id in
                if id == "B" {
                    loaderEntered.open()
                    await letLoaderFinish.wait()
                    return bState
                }
                return .empty
            },
            founderPrefsSaver: { cid, prefs in
                writes.append((cid: cid, prefs: prefs)); return true
            })

        await store.hydrate(companyId: "A")
        XCTAssertFalse(store.isHydrating)

        let hydrateTask = Task { await store.hydrate(companyId: "B") }
        await loaderEntered.wait()
        XCTAssertEqual(store.companyId, "B")   // already flipped to the incoming account
        XCTAssertTrue(store.isHydrating)       // ...but B's company hasn't loaded yet

        var prefs = FounderPrefs()
        prefs.style.customInstructions = "A's instruction"
        await store.setFounderPrefs(prefs)

        letLoaderFinish.open()
        await hydrateTask.value

        XCTAssertTrue(writes.isEmpty,
                      "setFounderPrefs must not write while a hydrate to a different " +
                      "account is in flight — got \(writes)")
        XCTAssertEqual(store.company.founderPrefs, FounderPrefs(),
                       "B's loaded prefs must not be clobbered by A's draft")
        XCTAssertEqual(store.company.brief.projectName, "B-Co")
    }

    /// Regression: every settings panel commits from an untracked `Task`, so two quick
    /// changes put two prefs writes in flight at once and Firestore can finish them in
    /// either order. The OLDER write completing last must NOT apply its value — panels read
    /// the next draft off `company.founderPrefs`, so a clobber here also gets re-persisted.
    ///
    /// The account is never switched, so `hydrationToken` cannot see this: it takes the
    /// per-write token to drop the stale commit.
    func test_overlappingPrefsWritesLeaveTheNewerValueInMemory() async {
        let olderEntered = OneShotGate()
        let letOlderFinish = OneShotGate()
        var finished: [String] = []

        let store = CompanyStore(loader: { _ in .empty },
                                 founderPrefsSaver: { _, prefs in
            let which = prefs.style.customInstructions
            if which == "older" {          // park the first write until the second is done
                olderEntered.open()
                await letOlderFinish.wait()
            }
            finished.append(which)
            return true
        })
        await store.hydrate(companyId: "u")

        var older = FounderPrefs(); older.style.customInstructions = "older"
        var newer = FounderPrefs(); newer.style.customInstructions = "newer"

        let olderWrite = Task { await store.setFounderPrefs(older) }
        await olderEntered.wait()
        await store.setFounderPrefs(newer)   // starts and completes while the older one is parked
        letOlderFinish.open()
        await olderWrite.value

        XCTAssertEqual(finished, ["newer", "older"],
                       "the older write has to be the one that lands last for this to test " +
                       "anything — got \(finished)")
        XCTAssertEqual(store.company.founderPrefs.style.customInstructions, "newer",
                       "an out-of-order older write must not clobber the newer choice")
        // Both writes still reach Firestore — sequencing drops the stale in-memory commit,
        // not the persistence.
        XCTAssertEqual(finished.count, 2)
    }
}
