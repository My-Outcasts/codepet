import XCTest
@testable import codepet

final class TrajectoryDetectorTests: XCTestCase {

    /// Fixed reference point; all signal dates are expressed as "days ago".
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func sig(
        _ dim: String,
        _ valence: String,
        daysAgo: Int,
        session: String
    ) -> AgencySignal {
        AgencySignal(
            id: "\(session)__\(dim)__\(valence)__\(daysAgo)",
            sessionId: session,
            observation: "obs",
            axis: "agency",
            signal: dim,
            valence: valence,
            evidence: "ev",
            language: "en",
            createdAt: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        )
    }

    private let G = "growth"
    private let S = "strength"

    // MARK: - Happy path

    func testRisingTrajectoryDetected() {
        let signals = [
            sig("verification", G, daysAgo: 30, session: "s1"),
            sig("verification", G, daysAgo: 25, session: "s2"),
            sig("verification", G, daysAgo: 20, session: "s3"),
            sig("verification", S, daysAgo: 3,  session: "s6"),
            // filler to clear the ≥6-session bar (does not itself qualify)
            sig("context", G, daysAgo: 18, session: "s4"),
            sig("prompting", G, daysAgo: 12, session: "s5"),
        ]
        let t = TrajectoryDetector.strongest(signals: signals, now: now)
        XCTAssertEqual(t?.signal, "verification")
        XCTAssertEqual(t?.earlierGrowthCount, 3)
        XCTAssertEqual(t?.recentStrengthCount, 1)
        XCTAssertEqual(t?.spanDays, 27)
        XCTAssertEqual(t?.signalValue, .verification)
    }

    // MARK: - Honesty guards

    func testRequiresRepeatedEarlierGrowth() {
        // Only ONE earlier growth flag → not a real, repeated edge.
        let signals = [
            sig("verification", G, daysAgo: 25, session: "s1"),
            sig("verification", S, daysAgo: 3,  session: "s2"),
            sig("context", G, daysAgo: 20, session: "s3"),
            sig("context", G, daysAgo: 19, session: "s4"),
            sig("scoping", G, daysAgo: 18, session: "s5"),
            sig("prompting", G, daysAgo: 10, session: "s6"),
        ]
        XCTAssertNil(TrajectoryDetector.strongest(signals: signals, now: now))
    }

    func testRequiresRecentStrengthNotJustSilence() {
        // Repeated early edge, then growth simply VANISHES — no affirmative
        // strength. Must NOT claim a win (the core honesty guarantee).
        let signals = [
            sig("verification", G, daysAgo: 30, session: "s1"),
            sig("verification", G, daysAgo: 25, session: "s2"),
            sig("verification", G, daysAgo: 20, session: "s3"),
            sig("context", G, daysAgo: 18, session: "s4"),
            sig("scoping", G, daysAgo: 12, session: "s5"),
            sig("prompting", S, daysAgo: 4,  session: "s6"),
        ]
        XCTAssertNil(
            TrajectoryDetector.detectAll(signals: signals, now: now)
                .first { $0.signal == "verification" }
        )
    }

    func testRecentGrowthStillOpenBlocksTrajectory() {
        // Earlier growth + a recent strength, BUT growth is still appearing in
        // the recent window → the edge is not closed.
        let signals = [
            sig("verification", G, daysAgo: 30, session: "s1"),
            sig("verification", G, daysAgo: 25, session: "s2"),
            sig("verification", S, daysAgo: 5,  session: "s3"),
            sig("verification", G, daysAgo: 2,  session: "s4"), // recent growth
            sig("context", G, daysAgo: 18, session: "s5"),
            sig("scoping", G, daysAgo: 11, session: "s6"),
        ]
        XCTAssertNil(TrajectoryDetector.strongest(signals: signals, now: now))
    }

    // MARK: - Volume / span gates

    func testRequiresMinimumSessions() {
        // Pattern qualifies, but only 4 distinct sessions (< 6).
        let signals = [
            sig("verification", G, daysAgo: 30, session: "s1"),
            sig("verification", G, daysAgo: 25, session: "s2"),
            sig("verification", G, daysAgo: 20, session: "s3"),
            sig("verification", S, daysAgo: 3,  session: "s4"),
        ]
        XCTAssertTrue(TrajectoryDetector.detectAll(signals: signals, now: now).isEmpty)
    }

    func testRequiresMinimumSpan() {
        // Eg≥2 and Rs≥1, but the whole journey spans only a few days.
        let signals = [
            sig("verification", G, daysAgo: 16, session: "s1"),
            sig("verification", G, daysAgo: 15, session: "s2"),
            sig("verification", S, daysAgo: 13, session: "s3"),
            sig("context", G, daysAgo: 30, session: "s4"),
            sig("scoping", G, daysAgo: 28, session: "s5"),
            sig("prompting", G, daysAgo: 22, session: "s6"),
        ]
        XCTAssertNil(
            TrajectoryDetector.detectAll(signals: signals, now: now)
                .first { $0.signal == "verification" }
        )
    }

    // MARK: - Ranking & matching

    func testStrongestPicksHighestSignalAndDetectAllOrders() {
        let signals = [
            // verification: Eg3 + Rs1 = 4
            sig("verification", G, daysAgo: 30, session: "s1"),
            sig("verification", G, daysAgo: 25, session: "s2"),
            sig("verification", G, daysAgo: 20, session: "s3"),
            sig("verification", S, daysAgo: 3,  session: "s7"),
            // prompting: Eg2 + Rs1 = 3
            sig("prompting", G, daysAgo: 28, session: "s4"),
            sig("prompting", G, daysAgo: 22, session: "s5"),
            sig("prompting", S, daysAgo: 5,  session: "s8"),
        ]
        let all = TrajectoryDetector.detectAll(signals: signals, now: now)
        XCTAssertEqual(all.map(\.signal), ["verification", "prompting"])
        XCTAssertEqual(TrajectoryDetector.strongest(signals: signals, now: now)?.signal, "verification")
    }

    func testDimensionMatchingIsCaseInsensitive() {
        let signals = [
            sig("Verification", G, daysAgo: 30, session: "s1"),
            sig("VERIFICATION", G, daysAgo: 25, session: "s2"),
            sig("verification", S, daysAgo: 3,  session: "s6"),
            sig("context", G, daysAgo: 20, session: "s3"),
            sig("context", G, daysAgo: 19, session: "s4"),
            sig("scoping", G, daysAgo: 14, session: "s5"),
        ]
        let t = TrajectoryDetector.strongest(signals: signals, now: now)
        XCTAssertEqual(t?.signal, "verification")
        XCTAssertEqual(t?.earlierGrowthCount, 2)
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(TrajectoryDetector.strongest(signals: [], now: now))
        XCTAssertTrue(TrajectoryDetector.detectAll(signals: [], now: now).isEmpty)
    }
}
