// codepetTests/MemoryDigestTests.swift
import XCTest
@testable import codepet

/// The Memory panel's summary wording lives in a pure enum, not inline in the view,
/// because `PetMemoryStore` is a `@MainActor` singleton backed by UserDefaults — the
/// only way to assert what the founder actually reads is to keep the sentence pure.
final class MemoryDigestTests: XCTestCase {
    func test_noSessionsReadsAsNothingYet() {
        XCTAssertEqual(MemoryDigest.codingActivityLine(memories: [:], lang: .en),
                       "No coding sessions yet.")
    }

    func test_summarisesSessionsAndStreak() {
        var m = PetMemory()
        m.totalSessions = 12
        m.currentStreak = 4
        let line = MemoryDigest.codingActivityLine(memories: ["/p": m], lang: .en)
        XCTAssertTrue(line.contains("12"), line)
        XCTAssertTrue(line.contains("4"), line)
    }

    func test_ignoresProjectsWithNoSessions() {
        var real = PetMemory(); real.totalSessions = 3
        let empty = PetMemory()
        let line = MemoryDigest.codingActivityLine(
            memories: ["/a": real, "/b": empty], lang: .en)
        XCTAssertTrue(line.contains("3"), line)
    }

    /// A project that has never been coded in must not drag the line to "0 sessions"
    /// — `memories` gains an entry per detected project, not per worked one.
    func test_allProjectsEmptyReadsAsNothingYet() {
        let line = MemoryDigest.codingActivityLine(
            memories: ["/a": PetMemory(), "/b": PetMemory()], lang: .en)
        XCTAssertEqual(line, "No coding sessions yet.")
    }

    func test_vietnameseIsTranslatedNotEnglish() {
        var m = PetMemory(); m.totalSessions = 7; m.currentStreak = 2
        let vi = MemoryDigest.codingActivityLine(memories: ["/p": m], lang: .vi)
        XCTAssertFalse(vi.contains("sessions"), vi)
        XCTAssertTrue(vi.contains("7"), vi)
        XCTAssertEqual(MemoryDigest.codingActivityLine(memories: [:], lang: .vi),
                       "Chưa có phiên lập trình nào.")
    }
}
