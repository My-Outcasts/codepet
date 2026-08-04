// codepetTests/FounderPrefsPersistenceTests.swift
import XCTest
@testable import codepet

@MainActor
final class FounderPrefsPersistenceTests: XCTestCase {
    func test_updateFounderPrefs_updatesStateAndWritesOnce() async {
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
        await store.updateFounderPrefs { $0 = prefs }

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
    func test_prefsWriteDroppedWhileHydratingADifferentAccount() async {
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
        await store.updateFounderPrefs { $0 = prefs }

        letLoaderFinish.open()
        await hydrateTask.value

        XCTAssertTrue(writes.isEmpty,
                      "a prefs write must not land while a hydrate to a different " +
                      "account is in flight — got \(writes)")
        XCTAssertEqual(store.company.founderPrefs, FounderPrefs(),
                       "B's loaded prefs must not be clobbered by A's draft")
        XCTAssertEqual(store.company.brief.projectName, "B-Co")
    }

    /// Regression: every settings panel commits from an untracked `Task`, so two quick
    /// changes put two prefs writes in flight at once and Firestore can finish them in
    /// either order. The OLDER write completing last must NOT apply its value — the panels seed
    /// their drafts off `company.founderPrefs`, so a clobber here also gets re-persisted.
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

        let olderWrite = Task { await store.updateFounderPrefs { $0 = older } }
        await olderEntered.wait()
        await store.updateFounderPrefs { $0 = newer }   // completes while the older one is parked
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

    /// Regression, THE settings-modal data-loss bug: three panels edit fields of one
    /// `founderPrefs` struct, and each `commit()` used to capture the whole struct and write it
    /// back. `company.founderPrefs` is only updated after the Firestore await, so a commit
    /// issued inside another panel's write window carried that panel's OLD field along with its
    /// own change — turn memory off, switch to Notifications, change a picker before the first
    /// write lands, and `memoryEnabled` silently reverts to `true`.
    ///
    /// `founderPrefsWriteToken` cannot catch this: both writes are legitimate and touch
    /// different fields, so neither should be dropped. The fix is that a commit applies only
    /// its own change, to the latest intended value — hence a closure, not a struct.
    func test_aCommitDuringAnotherPanelsWriteDoesNotResurrectTheStaleField() async {
        let memoryWriteEntered = OneShotGate()
        let letMemoryWriteFinish = OneShotGate()
        var writes: [FounderPrefs] = []

        let store = CompanyStore(loader: { _ in .empty }, founderPrefsSaver: { _, prefs in
            writes.append(prefs)
            // Park the memory write — the one that turns it off and touches nothing else.
            if !prefs.memoryEnabled && prefs.notifications.isEmpty {
                memoryWriteEntered.open()
                await letMemoryWriteFinish.wait()
            }
            return true
        })
        await store.hydrate(companyId: "u")

        // MemoryPanel: the Enable-memory switch goes off.
        let memoryWrite = Task { await store.updateFounderPrefs { $0.memoryEnabled = false } }
        await memoryWriteEntered.wait()
        XCTAssertTrue(store.company.founderPrefs.memoryEnabled,
                      "the memory write hasn't returned yet — that window is what this reproduces")

        // NotificationsPanel, inside that window: a picker changes.
        await store.updateFounderPrefs { $0.notifications["sessionNudges"] = .off }

        letMemoryWriteFinish.open()
        await memoryWrite.value

        XCTAssertFalse(store.company.founderPrefs.memoryEnabled,
                       "turning memory off must survive another panel's commit")
        XCTAssertEqual(store.company.founderPrefs.notifications, ["sessionNudges": .off],
                       "...and the notifications change must survive too")
        // The document sees the union, not one field at a time: the second write carries both.
        XCTAssertEqual(writes.last?.memoryEnabled, false)
        XCTAssertEqual(writes.last?.notifications, ["sessionNudges": .off])
    }

    /// A commit issued while another account is being hydrated is dropped (the test above
    /// this one), so its intent must not survive to be composed onto the INCOMING founder's
    /// next settings change.
    func test_anInFlightIntentDoesNotFollowTheFounderIntoAnotherAccount() async {
        let writeEntered = OneShotGate()
        let letWriteFinish = OneShotGate()
        var writes: [FounderPrefs] = []

        let store = CompanyStore(loader: { _ in .empty }, founderPrefsSaver: { _, prefs in
            writes.append(prefs)
            if !prefs.memoryEnabled {
                writeEntered.open()
                await letWriteFinish.wait()
            }
            return true
        })
        await store.hydrate(companyId: "A")

        let write = Task { await store.updateFounderPrefs { $0.memoryEnabled = false } }
        await writeEntered.wait()
        await store.hydrate(companyId: "B")     // account switch lands mid-write
        letWriteFinish.open()
        await write.value

        // B's own change must not carry A's memory switch.
        await store.updateFounderPrefs { $0.notifications["sessionNudges"] = .off }
        XCTAssertTrue(store.company.founderPrefs.memoryEnabled,
                      "A's in-flight intent must not be composed onto B's preferences")
        XCTAssertEqual(writes.last?.memoryEnabled, true)
    }

    /// The store owns the redundant-write check, and it compares against the latest INTENDED
    /// value rather than the visible one: a change that reverts an in-flight change back to
    /// what is still on screen is a real write, and a no-op closure is not.
    func test_theStoreSkipsANoOpChangeButNotARevertOfAnInFlightOne() async {
        let firstEntered = OneShotGate()
        let letFirstFinish = OneShotGate()
        var writes: [FounderPrefs] = []

        let store = CompanyStore(loader: { _ in .empty }, founderPrefsSaver: { _, prefs in
            writes.append(prefs)
            if !prefs.memoryEnabled {
                firstEntered.open()
                await letFirstFinish.wait()
            }
            return true
        })
        await store.hydrate(companyId: "u")

        await store.updateFounderPrefs { $0.memoryEnabled = true }   // already true
        XCTAssertTrue(writes.isEmpty, "a change that changes nothing must not write")

        let off = Task { await store.updateFounderPrefs { $0.memoryEnabled = false } }
        await firstEntered.wait()
        // Flipped back ON while the OFF write is still in flight. `company.founderPrefs` still
        // says `true`, so comparing against it would drop this — but the founder's intent
        // genuinely changed, twice.
        await store.updateFounderPrefs { $0.memoryEnabled = true }
        letFirstFinish.open()
        await off.value

        XCTAssertEqual(writes.count, 2, "the revert has to reach Firestore — got \(writes)")
        XCTAssertTrue(store.company.founderPrefs.memoryEnabled)
    }
}
