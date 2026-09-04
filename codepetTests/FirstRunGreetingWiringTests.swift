// codepetTests/FirstRunGreetingWiringTests.swift
import XCTest
@testable import codepet

/// Guards on the first-run greeting actually reaching a founder.
///
/// `FirstRunGreetingBuilder` wrote the right message, carried an inline action to start the
/// first task, and was covered by two suites — and nothing called it. `seedFirstRunGreeting`
/// was reachable only from the first-run enrich interview's completion, and
/// `startEnrichInterviewIfNeeded` has no caller in the app; its own comment says so. So a new
/// founder got the hero and a beacon card, and the message that would have oriented them was
/// unreachable. Reported by the founder, 4 Sep: "as soon as they log in, they're directed
/// straight to a task card — where's the initial prompt?"
@MainActor
final class FirstRunGreetingWiringTests: XCTestCase {

    // MARK: - Task 1: the field and its wire shape

    /// Millis, not ISO — `introSeenAt` and `firstApprovalAt` beside it are numbers.
    func testGreetedPayloadIsEpochMillis() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(CompanyData.greetedPayload(at)["greetedAt"] as? Double,
                       1_700_000_000_000)
    }

    /// **The landmine.** `CompanyState.init(from:)` is hand-written because Swift's synthesised
    /// `Decodable` throws `keyNotFound` rather than falling back to a declared default. Every
    /// company document in Firestore predates this field.
    func testACompanyDocumentWithoutTheFieldStillDecodes() throws {
        let json = #"{"companionId":"byte","stage":"building"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertNil(state.greetedAt)
        XCTAssertEqual(state.companionId, "byte")
    }

    func testItRoundTripsWhenPresent() throws {
        var state = CompanyState.empty
        state.greetedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try JSONDecoder().decode(
            CompanyState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back.greetedAt?.timeIntervalSince1970, 1_700_000_000)
    }
}
