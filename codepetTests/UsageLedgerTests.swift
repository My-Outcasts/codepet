// codepetTests/UsageLedgerTests.swift
import XCTest
@testable import codepet

/// CP-028: the room's cost leaves the chat and is added up per local day for Settings → Usage.
/// Every ledger here writes to its own throwaway defaults suite — never `.standard`, which is the
/// founder's real preferences (the #117 leak).
final class UsageLedgerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UsageLedgerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A fixed calendar so "the same day" does not depend on the machine running the suite.
    private var saigon: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return c
    }

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testRunsOnTheSameLocalDayAddUp() {
        let ledger = DefaultsUsageLedger(defaults: defaults, calendar: saigon)
        ledger.record(costUsd: 0.457, at: at("2026-09-28T03:10:00Z"))
        ledger.record(costUsd: 0.212, at: at("2026-09-28T09:40:00Z"))
        let day = ledger.day(at("2026-09-28T12:00:00Z"))
        XCTAssertEqual(day.runs, 2)
        XCTAssertEqual(day.costUsd, 0.669, accuracy: 0.0001)
    }

    /// 23:30 Saigon on the 28th and 00:30 on the 29th are an hour apart but on different days.
    func testTheDayIsTheFoundersLocalDayNotUTC() {
        let ledger = DefaultsUsageLedger(defaults: defaults, calendar: saigon)
        ledger.record(costUsd: 0.10, at: at("2026-09-28T16:30:00Z"))
        ledger.record(costUsd: 0.20, at: at("2026-09-28T17:30:00Z"))
        XCTAssertEqual(ledger.day(at("2026-09-28T16:30:00Z")).runs, 1)
        XCTAssertEqual(ledger.day(at("2026-09-28T17:30:00Z")).costUsd, 0.20, accuracy: 0.0001)
    }

    func testADayWithNoRunsIsZero() {
        let ledger = DefaultsUsageLedger(defaults: defaults, calendar: saigon)
        XCTAssertEqual(ledger.day(at("2026-09-28T03:00:00Z")), UsageDay(runs: 0, costUsd: 0))
    }

    /// A relaunch reads the same totals back.
    func testTotalsSurviveANewLedgerOnTheSameDefaults() {
        DefaultsUsageLedger(defaults: defaults, calendar: saigon).record(costUsd: 0.3, at: at("2026-09-28T03:00:00Z"))
        let reopened = DefaultsUsageLedger(defaults: defaults, calendar: saigon)
        XCTAssertEqual(reopened.day(at("2026-09-28T05:00:00Z")).runs, 1)
    }

    /// Only the last 30 days are kept, so the stored dictionary cannot grow forever.
    func testDaysOlderThanThirtyAreDropped() {
        let ledger = DefaultsUsageLedger(defaults: defaults, calendar: saigon)
        ledger.record(costUsd: 0.1, at: at("2026-08-01T03:00:00Z"))
        ledger.record(costUsd: 0.1, at: at("2026-09-28T03:00:00Z"))
        XCTAssertEqual(ledger.day(at("2026-08-01T03:00:00Z")).runs, 0, "a 58-day-old day is pruned")
        XCTAssertEqual(ledger.day(at("2026-09-28T03:00:00Z")).runs, 1)
    }

    // MARK: - Copy

    func testTodayCopyNamesTheMeetingsAndTheEstimate() {
        XCTAssertEqual(UsageCopy.todayValue(UsageDay(runs: 2, costUsd: 0.669), lang: .en), "2 meetings · ~$0.67")
        XCTAssertEqual(UsageCopy.todayValue(UsageDay(runs: 1, costUsd: 0.212), lang: .en), "1 meeting · ~$0.21")
        XCTAssertEqual(UsageCopy.todayValue(UsageDay(runs: 2, costUsd: 0.669), lang: .vi), "2 cuộc họp · ~$0.67")
        XCTAssertEqual(UsageCopy.todayValue(UsageDay(runs: 0, costUsd: 0), lang: .en), "None yet")
        XCTAssertEqual(UsageCopy.todayValue(UsageDay(runs: 0, costUsd: 0), lang: .vi), "Chưa có")
    }

    /// The figure is an API-price estimate of plan usage, not a bill, and the row must say so.
    func testTheDescriptionSaysItIsAnEstimateNotABill() {
        XCTAssertTrue(UsageCopy.todayDetail(.en).contains("not billed"))
        XCTAssertTrue(UsageCopy.todayDetail(.vi).contains("không bị tính phí"))
    }
}

/// The store side: every room that reports telemetry lands in the ledger exactly once, when the
/// room ends. The ledger is injected, so nothing here reaches `UserDefaults.standard`.
@MainActor
final class CompanyStoreUsageTests: XCTestCase {
    private typealias F = TeamBuildFixture
    private var root: URL!

    override func setUp() {
        super.setUp()
        CompanyStore.execStepNanos = 0
        root = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    static func telemetry(_ cost: Double) -> VCTelemetry {
        try! JSONDecoder().decode(VCTelemetry.self, from: Data(
            #"{"tokens_per_agent":{},"cost_estimate_usd":\#(cost),"stopped_reason":null}"#.utf8))
    }

    /// A room like `TeamBuildFixture.room`, with the `telemetry` frame the orchestrator sends
    /// just before `done` (twice when `repeatTelemetry`, as a reconnect could).
    private static func room(cost: Double?, repeatTelemetry: Bool = false, probe: F.Probe)
    -> (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        { _ in
            probe.vcCalls += 1
            return AsyncThrowingStream { cont in
                Task {
                    cont.yield(.runStarted(runId: "r1"))
                    cont.yield(.routing(F.routing("multi_agent")))
                    cont.yield(.brief(F.aBrief("Ship a single landing page")))
                    if let cost {
                        cont.yield(.telemetry(telemetry(cost)))
                        if repeatTelemetry { cont.yield(.telemetry(telemetry(cost))) }
                    }
                    cont.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                    cont.finish()
                }
            }
        }
    }

    func testARoomsCostIsRecordedOnceWhenItEnds() async {
        let probe = F.Probe(), ledger = InMemoryUsageLedger()
        let s = F.store(probe: probe, root: root, room: Self.room(cost: 0.457, repeatTelemetry: true, probe: probe),
                        usageLedger: ledger)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let recorded = await F.waitFor { ledger.day(Date()).runs > 0 }
        XCTAssertTrue(recorded, "the room's cost never reached the ledger")
        _ = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertEqual(ledger.day(Date()), UsageDay(runs: 1, costUsd: 0.457), "one room, one entry")
    }

    func testARoomWithoutTelemetryRecordsNothing() async {
        let probe = F.Probe(), ledger = InMemoryUsageLedger()
        let s = F.store(probe: probe, root: root, room: Self.room(cost: nil, probe: probe), usageLedger: ledger)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let planned = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertTrue(planned, "precondition: the room ended and planned")
        XCTAssertEqual(ledger.day(Date()).runs, 0)
    }
}
