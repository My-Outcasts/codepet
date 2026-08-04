// codepetTests/CompanyStoreForgetDecisionTests.swift
import XCTest
@testable import codepet

/// The delete half of the Memory panel. Facts the founder's team was told are the
/// trust-critical store — "forget this" has to actually reach the document, remove only
/// the row that was tapped, and never write into the wrong account.
@MainActor
final class CompanyStoreForgetDecisionTests: XCTestCase {
    private static func entry(_ topic: String) -> DecisionEntry {
        DecisionEntry(topic: topic, statement: "\(topic) is settled", source: "chat", updatedAt: 1)
    }

    private static func company(_ decisions: [DecisionEntry]) -> CompanyState {
        CompanyState(brief: CompanyBrief(projectName: "Co"), departments: [], library: [],
                     stage: .idea, companionId: "byte", onboardedAt: Date(), decisions: decisions)
    }

    func test_forgetRemovesExactlyOneEntryAndWritesOnce() async {
        var writes: [[DecisionEntry]] = []
        let s = CompanyStore(loader: { _ in Self.company([Self.entry("a"), Self.entry("b"), Self.entry("c")]) },
                             decisionsSaver: { _, d in writes.append(d); return true })
        await s.hydrate(companyId: "u")

        await s.forgetDecision(Self.entry("b"))

        XCTAssertEqual(s.company.decisions.map(\.topic), ["a", "c"])
        XCTAssertEqual(writes.count, 1, "exactly one write, through the existing decisionsSaver")
        XCTAssertEqual(writes.first?.map(\.topic), ["a", "c"])
    }

    /// Two rows can share a statement only by sharing a topic (the merge key), but a doc
    /// written before the merge existed can still hold duplicates — forgetting must drop
    /// ONE row, not silently sweep every match.
    func test_forgetRemovesOnlyOneOfTwoIdenticalEntries() async {
        let dup = Self.entry("pricing")
        let s = CompanyStore(loader: { _ in Self.company([dup, dup]) },
                             decisionsSaver: { _, _ in true })
        await s.hydrate(companyId: "u")

        await s.forgetDecision(dup)

        XCTAssertEqual(s.company.decisions.count, 1)
    }

    /// A stale row (already superseded by a `remember_fact` merge between render and tap)
    /// must be a no-op, not a write that re-uploads the same array.
    func test_forgettingSomethingAlreadyGoneDoesNotWrite() async {
        var writes = 0
        let s = CompanyStore(loader: { _ in Self.company([Self.entry("a")]) },
                             decisionsSaver: { _, _ in writes += 1; return true })
        await s.hydrate(companyId: "u")

        await s.forgetDecision(Self.entry("nope"))

        XCTAssertEqual(writes, 0)
        XCTAssertEqual(s.company.decisions.map(\.topic), ["a"])
    }

    /// Regression, the same hazard `setFounderName`/`setFounderPrefs` carry: `hydrate`
    /// flips `companyId` to the INCOMING account BEFORE `company` is loaded for it, so a
    /// forget tapped in that window (settings still open across a sign-out / account
    /// switch) must not delete out of the incoming founder's document.
    func test_forgetDroppedWhileHydratingADifferentAccount() async {
        let loaderEntered = OneShotGate()
        let letLoaderFinish = OneShotGate()
        var writes: [(cid: String, decisions: [DecisionEntry])] = []

        let bState = Self.company([Self.entry("b-only")])

        let s = CompanyStore(
            loader: { id in
                if id == "B" {
                    loaderEntered.open()
                    await letLoaderFinish.wait()
                    return bState
                }
                return Self.company([Self.entry("a1"), Self.entry("a2")])
            },
            decisionsSaver: { cid, d in writes.append((cid: cid, decisions: d)); return true })

        await s.hydrate(companyId: "A")
        XCTAssertFalse(s.isHydrating)

        let hydrateTask = Task { await s.hydrate(companyId: "B") }
        await loaderEntered.wait()
        XCTAssertEqual(s.companyId, "B")   // already flipped to the incoming account
        XCTAssertTrue(s.isHydrating)       // ...but B's company hasn't loaded yet

        await s.forgetDecision(Self.entry("a1"))

        letLoaderFinish.open()
        await hydrateTask.value

        XCTAssertTrue(writes.isEmpty,
                      "forgetDecision must not write while a hydrate to a different " +
                      "account is in flight — got \(writes)")
        XCTAssertEqual(s.company.decisions.map(\.topic), ["b-only"],
                       "B's loaded decisions must survive A's forget")
    }
}
