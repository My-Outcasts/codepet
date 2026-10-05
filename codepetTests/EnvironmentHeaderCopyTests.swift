// codepetTests/EnvironmentHeaderCopyTests.swift
import XCTest
@testable import codepet

/// The Environment header names the founder's stage. It read "Based on your **building**" —
/// the stage dropped in where a noun belongs, which only reads for "idea" and "prototype".
/// Found testing as a non-technical founder, 5 Oct.
final class EnvironmentHeaderCopyTests: XCTestCase {
    private let stages = ["Idea", "Prototype", "Building", "Private beta", "Launched"]

    func testEveryStageReadsAsAStage() {
        for s in stages {
            let p = EnvironmentHeaderCopy.parts(stage: s, needsYouCount: 0, lang: .en)
            let line = p.lead + p.stage + p.tail
            XCTAssertTrue(line.contains(" stage"), line)
            XCTAssertFalse(line.contains("your \(s.lowercased())"), line)
        }
    }

    func testVietnameseNamesTheStageToo() {
        let p = EnvironmentHeaderCopy.parts(stage: "Building", needsYouCount: 0, lang: .vi)
        XCTAssertTrue((p.lead + p.stage + p.tail).contains("giai đoạn"))
    }

    func testEmptyStageFallsBackToBuilding() {
        XCTAssertEqual(EnvironmentHeaderCopy.parts(stage: "  ", needsYouCount: 0, lang: .en).stage, "building")
        XCTAssertEqual(EnvironmentHeaderCopy.parts(stage: nil, needsYouCount: 0, lang: .en).stage, "building")
    }

    func testAccountsToConnectAreCounted() {
        XCTAssertTrue(EnvironmentHeaderCopy.parts(stage: "Idea", needsYouCount: 1, lang: .en).tail
            .contains("connect 1 account."))
        XCTAssertTrue(EnvironmentHeaderCopy.parts(stage: "Idea", needsYouCount: 2, lang: .en).tail
            .contains("connect 2 accounts."))
        XCTAssertTrue(EnvironmentHeaderCopy.parts(stage: "Idea", needsYouCount: 0, lang: .en).tail.hasSuffix("."))
    }
}
