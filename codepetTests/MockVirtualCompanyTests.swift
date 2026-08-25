// codepetTests/MockVirtualCompanyTests.swift
import XCTest
@testable import codepet

/// Guards on the mocked room.
///
/// The point of building the fixture as wire JSON rather than as Swift values is
/// that these assertions are then meaningful: `VirtualCompanyEvent.from(frame:)`
/// returns nil for a payload that will not decode, so a renamed key in the contract
/// shows up here as a missing frame instead of as a card that quietly never renders.
final class MockVirtualCompanyTests: XCTestCase {

    private let ask = "Should we ship the paywall before launch?"

    private func events() -> [VirtualCompanyEvent] {
        MockVirtualCompany.frames(ask: ask).compactMap { VirtualCompanyEvent.from(frame: $0) }
    }

    /// Every frame decodes. `from(frame:)` drops what it cannot parse, so a silent
    /// nil is exactly the failure this fixture exists to make loud.
    func testEveryFrameDecodes() {
        let frames = MockVirtualCompany.frames(ask: ask)
        for frame in frames {
            XCTAssertNotNil(VirtualCompanyEvent.from(frame: frame),
                            "the \(frame.event) frame does not decode — key drift in the contract")
        }
        XCTAssertEqual(events().count, frames.count)
    }

    /// A quote in the founder's question must not break the routing frame. Naive
    /// interpolation would produce invalid JSON and drop the frame that carries the
    /// whole room, and it would do it silently.
    func testAnAskContainingQuotesStillProducesAValidRoom() {
        let nasty = #"Should we ship the "free" tier — or not? \ backslash"#
        let decoded = MockVirtualCompany.frames(ask: nasty)
            .compactMap { VirtualCompanyEvent.from(frame: $0) }
        XCTAssertEqual(decoded.count, MockVirtualCompany.frames(ask: nasty).count)
        guard case .routing(let routing)? = decoded.first(where: {
            if case .routing = $0 { return true } else { return false }
        }) else { return XCTFail("no routing frame") }
        XCTAssertEqual(routing.realQuestion, nasty, "the founder's words were mangled")
    }

    /// Rule 2: never collapse the positions into one "we agree" paragraph. Consensus
    /// is what a fixture fakes most easily, and `runSynthesis` throws on a brief that
    /// buries dissent server-side — so the mock has to actually disagree.
    func testTheRoomGenuinelyDisagrees() {
        var stances: [String] = []
        var hardBlockers = 0
        for event in events() {
            if case .agentPosition(_, let position) = event {
                stances.append(position.stance)
                if position.hardBlocker != nil { hardBlockers += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(Set(stances).count, 2, "every department agrees: \(stances)")
        XCTAssertTrue(stances.contains("do_not_proceed"), "nobody objects")
        XCTAssertGreaterThan(hardBlockers, 0, "no hard blocker — nothing is really at stake")
    }

    /// Rule 4: each side's `what_would_change_my_mind` is on the conflict card,
    /// because that is what teaches that disagreement is settled by evidence.
    func testEveryNegotiationTurnSaysWhatWouldChangeItsMind() {
        var turns = 0
        for event in events() {
            if case .negotiationRound(let round) = event {
                for turn in round.turns {
                    turns += 1
                    XCTAssertFalse(turn.whatWouldChangeMyMind.isEmpty,
                                   "\(turn.agent) will not say what would change its mind")
                    XCTAssertFalse(turn.preciseDisagreement.isEmpty)
                }
            }
        }
        XCTAssertGreaterThan(turns, 1, "a negotiation needs two sides")
    }

    /// Rules 3, 5 and 6: the real disagreement verbatim, an either/or the founder
    /// owns rather than "it's up to you", and `unresolved` as a valid outcome.
    func testTheBriefEndsOnTheTradeoffAndNotOnItsUpToYou() {
        guard case .brief(let brief)? = events().first(where: {
            if case .brief = $0 { return true } else { return false }
        }) else { return XCTFail("no brief") }
        XCTAssertFalse(brief.theRealDisagreement.isEmpty)
        XCTAssertTrue(brief.tradeoffFounderMustOwn.lowercased().contains("either"),
                      "the brief does not end on an either/or")
        XCTAssertFalse(brief.tradeoffFounderMustOwn.lowercased().contains("up to you"),
                       "rule 5 forbids exactly this phrasing")
        XCTAssertTrue(brief.unresolved, "rule 6: unresolved is an answer, and worth showing")
    }

    /// The devil's advocate is not a department and must not be given one — a
    /// department key would hand it a colour and misrepresent what it is.
    func testTheDevilsAdvocateCarriesNoDepartment() {
        guard case .devilsAdvocate(let meta, let verdict)? = events().first(where: {
            if case .devilsAdvocate = $0 { return true } else { return false }
        }) else { return XCTFail("no devil's advocate") }
        XCTAssertNil(meta.departmentKey)
        XCTAssertFalse(verdict.objections.isEmpty)
    }

    /// Nothing was spent, so the ledger must not claim otherwise. A fixture
    /// reporting the live run's ~$0.20 would invent a charge in the one place a
    /// founder looks for real ones.
    func testAMockedRoomReportsNoCost() {
        guard case .telemetry(let telemetry)? = events().first(where: {
            if case .telemetry = $0 { return true } else { return false }
        }) else { return XCTFail("no telemetry") }
        XCTAssertEqual(telemetry.costEstimateUsd, 0)
        XCTAssertTrue(telemetry.tokensPerAgent.isEmpty)
    }

    /// Four seats is the server-side cap `parseRoutingToolInput` enforces, and the
    /// number `RoomOffer` prints on the menu item. A fixture seating more would make
    /// that label a lie.
    func testTheRoomSeatsNoMoreThanTheCap() {
        guard case .routing(let routing)? = events().first(where: {
            if case .routing = $0 { return true } else { return false }
        }) else { return XCTFail("no routing") }
        XCTAssertLessThanOrEqual(routing.agents.count, RoomOffer.seats)
        XCTAssertEqual(routing.decision, "multi_agent", "a single agent is not a room")
    }
}
