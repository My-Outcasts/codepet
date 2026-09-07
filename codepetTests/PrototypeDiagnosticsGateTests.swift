import XCTest
@testable import codepet

/// `FirestoreDiagnosticsSink` writes to `companies/{uid}/diagnostics` — the founder's real
/// company document. In prototype mode the company is a fixture, so those events used to land
/// in her live subtree, mixed with real ones. `PrototypeMode`'s gate was checked in
/// `CompanyData` only, which covers savers, not a sink that writes its own path.
///
/// Safe to drive `PrototypeMode` here: under XCTest its `store` is a scratch suite, wiped on
/// creation (the #117/#120 fix), so this cannot touch the founder's own preference.
final class PrototypeDiagnosticsGateTests: XCTestCase {

    private var restore: Bool!

    override func setUp() {
        super.setUp()
        restore = PrototypeMode.isOn
    }
    override func tearDown() {
        PrototypeMode.set(restore)
        super.tearDown()
    }

    /// **The leak, and the fix, in one comparison.**
    ///
    /// `true` means "dropped, never buffered" — the sink's own convention for a destination
    /// that is never coming, matching the opted-out branch. With prototype mode off the sink
    /// falls through to its next guard and reports `false` (not reachable: the test host
    /// configures no `FirebaseApp`). So the two states must differ, and the difference is
    /// precisely the gate — remove the guard and both become `false`.
    func testPrototypeModeDropsTheEventAndOffModeDoesNot() throws {
        let sink = FirestoreDiagnosticsSink()
        let payload: [String: Any] = ["kind": "selfTest", "site": "sessionLifecycle"]

        XCTAssertTrue(PrototypeMode.set(true), "could not enter prototype mode")
        XCTAssertTrue(sink.send(payload),
                      "prototype mode must DROP the event (true), not buffer it")

        XCTAssertTrue(PrototypeMode.set(false), "could not leave prototype mode")
        XCTAssertFalse(sink.send(payload),
                       "with the gate open the sink must fall through to its reachability guard")
    }

    /// The gate must not depend on being signed in or on Firebase being configured — it is
    /// "not sending" regardless, which is why it is checked first.
    func testTheGateHoldsWithNoFirebaseAndNobodySignedIn() {
        XCTAssertTrue(PrototypeMode.set(true))
        XCTAssertTrue(FirestoreDiagnosticsSink().send([:]),
                      "an empty payload in prototype mode is still dropped, not buffered")
    }

    // MARK: - The line it logs instead

    /// Gating the delivery must not lose the event: the message carries the whole payload,
    /// because prototype mode is DEBUG-only and the unified log is how this module is read.
    func testTheHeldMessageNamesTheReasonAndCarriesThePayload() {
        let m = DiagnosticsLog.heldByPrototypeMode(["kind": "crash", "site": "chat"])
        XCTAssertTrue(m.contains("prototype mode"), m)
        XCTAssertTrue(m.contains("kind=crash"), m)
        XCTAssertTrue(m.contains("site=chat"), m)
    }

    /// **Sorted keys, and it matters.** `[String: Any]` has no stable iteration order, so an
    /// unsorted render would emit a different line for the same event on every run. Two dicts
    /// built in opposite insertion orders must render identically.
    func testTheRenderIsDeterministicRegardlessOfInsertionOrder() {
        var a: [String: Any] = [:]
        a["zeta"] = 1; a["alpha"] = 2; a["mid"] = 3
        var b: [String: Any] = [:]
        b["mid"] = 3; b["alpha"] = 2; b["zeta"] = 1
        XCTAssertEqual(DiagnosticsLog.heldByPrototypeMode(a),
                       DiagnosticsLog.heldByPrototypeMode(b))
        // And the order is the sorted one, not whichever the dictionary happened to yield.
        let m = DiagnosticsLog.heldByPrototypeMode(a)
        let ia = try? XCTUnwrap(m.range(of: "alpha=")?.lowerBound)
        let iz = try? XCTUnwrap(m.range(of: "zeta=")?.lowerBound)
        if let ia, let iz { XCTAssertLessThan(ia, iz, "keys are not in sorted order: \(m)") }
    }

    /// An empty payload still explains itself rather than logging a bare colon.
    func testAnEmptyPayloadStillNamesTheReason() {
        XCTAssertTrue(DiagnosticsLog.heldByPrototypeMode([:]).contains("prototype mode"))
    }
}

// MARK: - The self-test must not blame the destination for the gate

extension PrototypeDiagnosticsGateTests {

    /// It has to name prototype mode AND say what to do, because the alternative message
    /// (`selfTestFailedNoDocument`) blames the channel for the gate holding the write.
    func testTheSelfTestSkipMessageNamesPrototypeModeAndTheWayOut() {
        let m = DiagnosticsLog.selfTestHeldByPrototypeMode()
        XCTAssertTrue(m.lowercased().contains("prototype mode"), m)
        XCTAssertTrue(m.lowercased().contains("skipped"), m)
        XCTAssertTrue(m.lowercased().contains("off"), "must say how to run it — \(m)")
    }

    /// And it must not read as a failure of the destination — the wording the old path used.
    func testTheSkipMessageDoesNotClaimTheDestinationFailed() {
        let m = DiagnosticsLog.selfTestHeldByPrototypeMode().lowercased()
        XCTAssertFalse(m.contains("fail"), m)
        XCTAssertFalse(m.contains("no document"), m)
    }
}
