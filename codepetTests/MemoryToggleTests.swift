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
    /// Tips) go quiet. Uses its OWN instance and restores the UserDefaults key, so it
    /// neither shares state with `PetMemoryStore.shared` nor eats real pet memory.
    func test_petMemoryStoreItselfGoesQuietWhenMemoryIsOff() {
        let key = "cp_pet_memory_v1"
        let saved = UserDefaults.standard.data(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let path = "/tmp/codepet-memory-gate-test"
        let store = PetMemoryStore()
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

        await s.setFounderPrefs(FounderPrefs())   // memory back on
        XCTAssertEqual(pushed.last, true, "setFounderPrefs must push the new pref: \(pushed)")

        var off = FounderPrefs(); off.memoryEnabled = false
        await s.setFounderPrefs(off)
        XCTAssertEqual(pushed.last, false)

        s.reset()
        XCTAssertEqual(pushed.last, true, "sign-out must restore the default: \(pushed)")
    }
}
