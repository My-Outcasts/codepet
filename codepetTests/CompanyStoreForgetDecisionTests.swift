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

    /// A fact the merge has REWRITTEN (same topic, new statement — `remember_fact` landing
    /// between render and tap) must still delete: identity is the topic, so the row the panel
    /// is showing and the row now on record are the same fact. Matching the statement too made
    /// the ✕ a silent no-op with no UI feedback — the panel's whole promise, broken.
    func test_forgetMatchesTheTopicAfterTheStatementWasRewritten() async {
        var writes: [[DecisionEntry]] = []
        let rewritten = DecisionEntry(topic: "Pricing", statement: "$39/mo now", source: "chat", updatedAt: 2)
        let s = CompanyStore(loader: { _ in Self.company([rewritten, Self.entry("b")]) },
                             decisionsSaver: { _, d in writes.append(d); return true })
        await s.hydrate(companyId: "u")

        // The row the founder tapped: the topic as it was rendered, with the OLD statement.
        await s.forgetDecision(DecisionEntry(topic: "pricing", statement: "pricing is settled",
                                             source: "chat", updatedAt: 1))

        XCTAssertEqual(s.company.decisions.map(\.topic), ["b"])
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.map(\.topic), ["b"])
    }

    /// A row for a topic that is not on record at all must be a no-op, not a write that
    /// re-uploads the same array.
    func test_forgettingSomethingAlreadyGoneDoesNotWrite() async {
        var writes = 0
        let s = CompanyStore(loader: { _ in Self.company([Self.entry("a")]) },
                             decisionsSaver: { _, _ in writes += 1; return true })
        await s.hydrate(companyId: "u")

        await s.forgetDecision(Self.entry("nope"))

        XCTAssertEqual(writes, 0)
        XCTAssertEqual(s.company.decisions.map(\.topic), ["a"])
    }

    /// A `remember_fact` merge landing INSIDE the delete's own write is the one race the
    /// hydration guard cannot catch: same account, same hydration token, so `companyId ==
    /// cid` still holds. Assigning a surviving list computed BEFORE the write erased the
    /// freshly-remembered fact from memory — and shipped that erasure to the document on the
    /// next write. The surviving list has to be re-derived from the CURRENT decisions, and the
    /// document converged on it.
    func test_forgetKeepsAFactRememberedDuringItsOwnSave() async {
        let saverEntered = OneShotGate()
        let letSaverFinish = OneShotGate()
        var writes: [[DecisionEntry]] = []
        let remembered = RememberedFact(topic: "pricing", statement: "$29/mo, no free tier")

        let s = CompanyStore(
            loader: { _ in Self.company([Self.entry("a"), Self.entry("b")]) },
            chatSender: { _ in nil },
            chatStreamer: { _ in
                AsyncThrowingStream { c in
                    c.yield(.delta("Noted"))
                    c.yield(.done(model: "m", cacheHit: false,
                                  action: ChatDoneAction(remember: [remembered])))
                    c.finish()
                }
            },
            decisionsSaver: { _, d in
                writes.append(d)
                if writes.count == 1 {      // the forget's own write — hold it open
                    saverEntered.open()
                    await letSaverFinish.wait()
                }
                return true
            })
        await s.hydrate(companyId: "u")

        let forget = Task { await s.forgetDecision(Self.entry("a")) }
        await saverEntered.wait()
        await s.sendChat("remember we charge $29/mo", language: .en)   // merge lands mid-write
        XCTAssertTrue(s.company.decisions.contains { $0.topic == "pricing" })
        letSaverFinish.open()
        await forget.value

        XCTAssertEqual(s.company.decisions.map(\.topic).sorted(), ["b", "pricing"],
                       "the fact remembered during the save must survive the delete: \(s.company.decisions)")
        XCTAssertEqual(writes.last?.map(\.topic).sorted(), ["b", "pricing"],
                       "and the document must converge on it: \(writes)")
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
