// codepetTests/CompanyStoreFounderNameTests.swift
import XCTest
@testable import codepet

/// One-shot async gate for deterministically interleaving two concurrent `Task`s in a
/// test, without relying on timing (`Task.sleep`). `open()` is idempotent and safe to
/// call before or after `wait()`.
private final class OneShotGate: @unchecked Sendable {
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

/// Regression (settings-modal review finding, Important): `PreferencesPanel` commits
/// its Preferred Name draft on `.onDisappear`, which can fire from inside a sign-out /
/// account-switch — i.e. AFTER `hydrate` has already flipped `companyId` to the
/// INCOMING account but BEFORE `company` has actually loaded for it. A `setFounderName`
/// that lands in that window must not write the OUTGOING founder's draft, on the
/// not-yet-loaded brief, into the INCOMING account's document.
@MainActor
final class CompanyStoreFounderNameTests: XCTestCase {
    func testSetFounderNameDroppedWhileHydratingADifferentAccount() async {
        let loaderEntered = OneShotGate()
        let letLoaderFinish = OneShotGate()
        var savedCalls: [(cid: String, founderName: String?)] = []

        let bState = CompanyState(brief: CompanyBrief(projectName: "B-Co"),
                                  departments: [], library: [], stage: .growth,
                                  companionId: "byte", onboardedAt: Date())

        let s = CompanyStore(
            loader: { id in
                if id == "B" {
                    // Signal we've entered the loader — by this point hydrate's
                    // synchronous prefix (companyId := "B", isHydrating = true) has
                    // definitely already run, since there is no suspension point
                    // between it and this call.
                    loaderEntered.open()
                    await letLoaderFinish.wait()
                    return bState
                }
                return .empty
            },
            saver: { cid, brief in
                savedCalls.append((cid: cid, founderName: brief.founderName))
                return true
            })

        // Establish account A first (instant loader, no race).
        await s.hydrate(companyId: "A")
        XCTAssertFalse(s.isHydrating)

        // Kick off the account switch to B. Its loader blocks until we release it,
        // so hydrate stays suspended between the companyId flip and the actual load —
        // exactly the hazard window described in the finding.
        let hydrateTask = Task { await s.hydrate(companyId: "B") }
        await loaderEntered.wait()
        XCTAssertEqual(s.companyId, "B")   // companyId already flipped to the incoming account
        XCTAssertTrue(s.isHydrating)       // ...but `company` has not been loaded for it yet

        // The enqueued draft-commit "task" (PreferencesPanel's onDisappear) runs right
        // here, while hydrate is suspended.
        await s.setFounderName("Jordan")

        // Let hydrate finish loading B normally.
        letLoaderFinish.open()
        await hydrateTask.value

        XCTAssertTrue(savedCalls.isEmpty,
                      "setFounderName must not write anything while a hydrate to a " +
                      "different account is in flight — got \(savedCalls)")
        XCTAssertNil(s.company.brief.founderName, "B's loaded brief must not be clobbered")
        XCTAssertEqual(s.company.brief.projectName, "B-Co")
    }

    /// Sanity check the same guard doesn't break the ordinary, no-race path.
    func testSetFounderNamePersistsNormally() async {
        var savedBrief: CompanyBrief?
        let s = CompanyStore(loader: { _ in .empty },
                             saver: { _, b in savedBrief = b; return true })
        await s.hydrate(companyId: "u")
        await s.setFounderName("Jordan")
        XCTAssertEqual(savedBrief?.founderName, "Jordan")
        XCTAssertEqual(s.company.brief.founderName, "Jordan")
    }
}
