// codepetTests/MemoryToggleTests.swift
import XCTest
@testable import codepet

/// One switch, TWO stores. `FounderPrefs.memoryEnabled` has to suppress both halves of
/// what the founder's team remembers — the facts it was TOLD (`company.decisions`, which
/// reach the model through `ChatContext.compose`) and the DERIVED coding activity
/// (`PetMemoryStore`, which reaches it through the summarize payloads). A switch that
/// silences one and leaks the other is worse than no switch, so each half is asserted
/// separately here, at the seam it actually passes through.
@MainActor
final class MemoryToggleTests: XCTestCase {
    private static let fact = DecisionEntry(topic: "pricing", statement: "$29/mo, no free tier",
                                            source: "chat", updatedAt: 1)

    private static func company(memoryEnabled: Bool) -> CompanyState {
        var prefs = FounderPrefs()
        prefs.memoryEnabled = memoryEnabled
        return CompanyState(brief: CompanyBrief(projectName: "Co"), departments: [], library: [],
                            stage: .idea, companionId: "byte", onboardedAt: Date(),
                            decisions: [fact], founderPrefs: prefs)
    }

    // MARK: - Store 1: facts the founder's team was told

    func test_composeCarriesDecisionsWhenMemoryIsOn() {
        let ctx = ChatContext.compose(brief: CompanyBrief(projectName: "Co"), tasks: [],
                                      decisions: [Self.fact], memoryEnabled: true)
        XCTAssertTrue(ctx.contains("$29/mo"), ctx)
    }

    func test_composeDropsDecisionsWhenMemoryIsOff() {
        let ctx = ChatContext.compose(brief: CompanyBrief(projectName: "Co"), tasks: [],
                                      decisions: [Self.fact], memoryEnabled: false)
        XCTAssertFalse(ctx.contains("$29/mo"), ctx)
        XCTAssertFalse(ctx.contains("pricing"), ctx)
        XCTAssertFalse(ctx.isEmpty)   // the brief still grounds the turn
    }

    /// End to end through the real send path: the request that goes on the wire must not
    /// carry the fact at all when the founder has memory off.
    func test_chatRequestContextHonoursTheSwitch() async {
        for enabled in [true, false] {
            var captured: String?
            let s = CompanyStore(
                loader: { _ in Self.company(memoryEnabled: enabled) },
                saver: { _, _ in true },
                chatSender: { _ in nil },
                chatStreamer: { req in
                    captured = req.context
                    return AsyncThrowingStream { c in
                        c.yield(.delta("ok"))
                        c.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction()))
                        c.finish()
                    }
                })
            await s.hydrate(companyId: "u")
            await s.sendChat("what are we charging?", language: .en)
            XCTAssertEqual(captured?.contains("$29/mo"), enabled,
                           "memoryEnabled=\(enabled) produced context: \(captured ?? "nil")")
        }
    }

    /// The OTHER route into a real model prompt: `extractDecisions` renders every fact it is
    /// handed as "- topic: statement" and sends it to Anthropic, so approving a deliverable
    /// with memory off must hand it nothing. Recording is deliberately untouched — what the
    /// deliverable itself locks in still lands in `company.decisions` and still persists.
    func test_approvalExtractDoesNotShipTheFactsStoreWhenMemoryIsOff() async {
        for enabled in [true, false] {
            var handed: [DecisionEntry]?
            var saved: [DecisionEntry]?
            let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                      drafted: true,
                                      draft: Deliverable(kind: .doc, title: "Positioning",
                                                         body: "for solo founders", sourceTaskId: "t1"))
            var seed = Self.company(memoryEnabled: enabled)
            seed.tasks = [drafted]
            let s = CompanyStore(loader: { _ in seed },
                                 tasksSaver: { _, _ in true },
                                 librarySaver: { _, _ in true },
                                 firstApprovalSaver: { _, _ in true },
                                 decisionsSaver: { _, d in saved = d; return true },
                                 decisionExtractor: { _, existing in
                                     handed = existing
                                     return [ExtractedDecision(topic: "positioning",
                                                               statement: "for solo founders",
                                                               source: "Positioning")]
                                 })
            await s.hydrate(companyId: "u")
            await s.approveTask(id: "t1")
            // rememberFromApproval is fire-and-forget — let it run.
            await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertEqual(handed?.isEmpty, !enabled,
                           "memoryEnabled=\(enabled) handed the extractor: \(handed ?? [])")
            XCTAssertEqual(handed?.contains { $0.statement.contains("$29/mo") }, enabled,
                           "memoryEnabled=\(enabled): the fact on record must reach the extract " +
                           "prompt only with memory ON — handed \(handed ?? [])")
            // Recording keeps working either way: off stops USE, not recording.
            XCTAssertTrue(s.company.decisions.contains { $0.topic == "positioning" },
                          "the approval's own fact must still be recorded: \(s.company.decisions)")
            XCTAssertTrue(saved?.contains { $0.topic == "positioning" } ?? false)
        }
    }

    /// CLAUDE.md is standing context the coding agent reads on every run, and it lives on
    /// disk — the most durable use of memory there is. Asserted on the pure seam
    /// (`claudeMdSeedDecisions` + `ClaudeMdBootstrap.compose`) rather than through
    /// `linkProject`, which would need a real folder and a security-scoped bookmark.
    func test_claudeMdSeedDropsTheFactsStoreWhenMemoryIsOff() async {
        for enabled in [true, false] {
            let s = CompanyStore(loader: { _ in Self.company(memoryEnabled: enabled) })
            await s.hydrate(companyId: "u")

            XCTAssertEqual(s.claudeMdSeedDecisions.isEmpty, !enabled)
            let seed = ClaudeMdBootstrap.compose(brief: s.company.brief,
                                                 decisions: s.claudeMdSeedDecisions)
            XCTAssertEqual(seed.contains("$29/mo"), enabled,
                           "memoryEnabled=\(enabled) seeded CLAUDE.md: \(seed)")
            XCTAssertTrue(seed.contains("Co"), "the brief still seeds the file: \(seed)")
        }
    }

    // MARK: - Store 2: derived coding activity

    func test_codingMemoryPromptHonoursTheSwitch() {
        var m = PetMemory()
        m.totalSessions = 5
        m.totalMinutes = 120
        XCTAssertNotNil(MemoryDigest.codingMemoryPrompt(m, memoryEnabled: true))
        XCTAssertNil(MemoryDigest.codingMemoryPrompt(m, memoryEnabled: false))
        // Pre-existing contract kept: no memory, or memory with no sessions, sends nothing.
        XCTAssertNil(MemoryDigest.codingMemoryPrompt(nil, memoryEnabled: true))
        XCTAssertNil(MemoryDigest.codingMemoryPrompt(PetMemory(), memoryEnabled: true))
    }

    /// The last link of store 2: the store itself consults the gate, so both payload
    /// accessors (`promptPayload(for:)` for the summarize CFs, `allMemoryPrompt()` for
    /// Tips) go quiet. Uses its OWN instance pointed at its OWN suite + key, so it can
    /// neither share state with `PetMemoryStore.shared` nor touch real founder memory:
    /// writing the live `cp_pet_memory_v1` key would put a save-restore race against any
    /// running app, whose `.shared.save()` can land after the restore.
    func test_petMemoryStoreItselfGoesQuietWhenMemoryIsOff() {
        let suiteName = "app.murror.codepet.tests.memoryGate"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let path = "/tmp/codepet-memory-gate-test"
        let store = PetMemoryStore(defaults: defaults, key: "cp_pet_memory_test")
        store.resetAll()
        store.recordSessionEnd(projectPath: path, sessionDate: Date(), durationMinutes: 30,
                               summary: "shipped the settings modal", lesson: nil, filesWorkedOn: [])
        XCTAssertNotNil(store.promptPayload(for: path))
        XCTAssertNotNil(store.allMemoryPrompt())

        store.setMemoryEnabled(false)
        XCTAssertNil(store.promptPayload(for: path))
        XCTAssertNil(store.allMemoryPrompt())
    }

    /// `PetMemoryStore` is a singleton the enrichers reach statically, so the founder's
    /// pref has to be PUSHED into it: on hydrate (the loaded value), on every prefs write,
    /// and back to the default on sign-out so the next account never inherits it.
    func test_companyStorePushesTheSwitchIntoPetMemory() async {
        var pushed: [Bool] = []
        let s = CompanyStore(loader: { _ in Self.company(memoryEnabled: false) },
                             founderPrefsSaver: { _, _ in true },
                             codingMemoryGate: { pushed.append($0) })
        await s.hydrate(companyId: "u")
        XCTAssertEqual(pushed.last, false, "hydrate must push the loaded pref: \(pushed)")

        await s.updateFounderPrefs { $0 = FounderPrefs() }   // memory back on
        XCTAssertEqual(pushed.last, true, "a prefs write must push the new pref: \(pushed)")

        var off = FounderPrefs(); off.memoryEnabled = false
        await s.updateFounderPrefs { $0 = off }
        XCTAssertEqual(pushed.last, false)

        s.reset()
        XCTAssertEqual(pushed.last, true, "sign-out must restore the default: \(pushed)")
    }
}
