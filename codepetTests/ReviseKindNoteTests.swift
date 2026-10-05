// codepetTests/ReviseKindNoteTests.swift
import XCTest
@testable import codepet

/// What each revise chip asks the model to do. Found testing as a non-technical founder
/// (5 Oct): "Shorter" on "Problem statement: the one sentence" shortened the reasoning under it
/// and left the one sentence — the doc's `call`, the thing the founder was looking at — exactly
/// as long as before. The note said only "Make it shorter".
final class ReviseKindNoteTests: XCTestCase {
    /// Shorter and Punchier must reach the headline / lead, not only the supporting sections.
    func testShorterAndPunchierNameTheLead() {
        for kind in [ReviseKind.shorter, .punchier] {
            let en = kind.note(.en).lowercased()
            XCTAssertTrue(en.contains("headline") || en.contains("opening"), en)
            XCTAssertTrue(kind.note(.vi).lowercased().contains("câu mở đầu"), kind.note(.vi))
        }
    }

    /// The server clips `reviseNote` at 500 characters (`runTaskCore.ts`); a note past that
    /// loses its tail silently.
    func testNotesFitTheServerClip() {
        for kind in ReviseKind.allCases {
            for lang in [AppLanguage.en, .vi] {
                XCTAssertLessThan(kind.note(lang).count, 500, "\(kind) \(lang)")
            }
        }
    }

    /// The preview names what it is waiting on — a revise takes about a minute, and a bare
    /// spinner in the corner read as nothing happening.
    func testBusyLabelsSayWhatIsHappening() {
        XCTAssertTrue(ReviseKind.busyLabel(.en).lowercased().contains("rewriting"))
        XCTAssertFalse(ReviseKind.busyLabel(.vi).isEmpty)
    }
}
