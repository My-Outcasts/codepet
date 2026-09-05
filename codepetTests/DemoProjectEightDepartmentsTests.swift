// codepetTests/DemoProjectEightDepartmentsTests.swift
import XCTest
@testable import codepet

/// Guards that the demo shows finished work from ALL EIGHT departments.
///
/// Measured 5 Sep: the 24-chapter walkthrough contained one `runBeacon`, one
/// `approveNewestDraft` and one `convene`, so ONE department produced work on camera — while
/// the board carried eight runnable tasks with eight real deliverables. Chapter 2 narrates
/// "eight departments, each speaking with its own pet" and the tour demonstrated one.
///
/// `LibraryView` already groups by department; it showed two groups because the fixture filed
/// three artifacts belonging to two departments, all of kind `doc`.
final class DemoProjectEightDepartmentsTests: XCTestCase {

    private var murror: DemoProject { .murror }

    // MARK: - Task 1: the six artifacts

    /// The six new titles must each resolve to their OWN entry, not to the catch-all and not to
    /// an existing entry's keywords.
    func testTheSixNewTitlesResolveToTheirOwnDeliverables() {
        let expected: [(title: String, kind: String, marker: String)] = [
            ("Choose what the app is built on", "doc", "on-device"),
            ("Work out what a month of inference costs", "sheet", "per active user"),
            ("Write down who this is not for", "doc", "not for"),
            ("Decide what happens on a bad night", "doc", "crisis"),
            ("Set up the weekly release rhythm", "checklist", "Thursday"),
            ("Write the data-deletion promise", "legal", "one tap"),
        ]
        for e in expected {
            let d = murror.deliverable(for: e.title)
            XCTAssertFalse(d.keywords.isEmpty, "\"\(e.title)\" fell through to the catch-all")
            XCTAssertEqual(d.kind, e.kind, e.title)
            // Case-insensitive: the marker is a content check, not a capitalisation check.
            // "On-device" and "One tap" both open sentences, so a case-sensitive `contains`
            // fails on correct content — which it did, on the first run.
            XCTAssertTrue(d.body.lowercased().contains(e.marker.lowercased()),
                          "\"\(e.title)\" resolved to the wrong entry: \(d.body.prefix(60))")
        }
    }

    /// **The shadowing guard.** `deliverable(for:)` returns the first entry whose keyword appears
    /// in the lowercased title, so a broad new keyword placed early silently steals another
    /// department's deliverable — no error, just Sales showing Engineering's work.
    func testTheNewKeywordsShadowNoExistingTitle() {
        let existing = [
            "Build the Murror landing page": "site",
            "Design the first-run flow": "screens",
            "Decide what free and paid mean": "sheet",
            "Ship an email capture": "checklist",
            "Find the first 20 users": "dms",
            "Answer the first questions": "doc",
            "Write the launch checklist": "plan",
            "Draft the privacy policy": "legal",
        ]
        for (title, kind) in existing {
            XCTAssertEqual(murror.deliverable(for: title).kind, kind,
                           "\"\(title)\" now resolves to the wrong entry")
        }
    }

    /// No filled body may leak an unsubstituted token to a founder's screen.
    ///
    /// Tokens are legitimate in the SOURCE — `{{product}}` is how the fixture stays project-
    /// agnostic — so this asserts on the FILLED output, which is what reaches a card.
    func testNoFilledBodyLeaksAToken() {
        for entry in murror.deliverables where !entry.keywords.isEmpty {
            let filled = MockChat.fill(entry.body, title: "T")
            XCTAssertFalse(filled.contains("{{"),
                           "unsubstituted token survives filling in \(entry.keywords)")
        }
    }
}
