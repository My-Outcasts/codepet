// codepetTests/FounderPrefsPersistenceTests.swift
import XCTest
@testable import codepet

/// One-shot async gate — same device as `CompanyStoreFounderNameTests`' `OneShotGate`,
/// duplicated (file-private) rather than shared so neither test file owns the other's
/// harness. Deterministically interleaves two concurrent `Task`s without `Task.sleep`.
private final class PrefsGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        lock.lock()
        if opened { lock.unlock(); return }
        lock.unlock()
        await withCheckedContinuation { cont in
            lock.lock()
            if opened { lock.unlock(); cont.resume(); return }
            continuation = cont
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}

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
        let loaderEntered = PrefsGate()
        let letLoaderFinish = PrefsGate()
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
}
