import XCTest
@testable import codepet

final class RoadmapBoardCopyTests: XCTestCase {
    // Web VERB map: only actionable states earn a verb chip.
    func testVerbsMatchWeb() {
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .codepetCanDo, .en), "Start")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsApproval, .en), "Review")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsYou, .en), "Add your input")
        XCTAssertNil(RoadmapBoardCopy.verb(for: .done, .en))
        XCTAssertNil(RoadmapBoardCopy.verb(for: .blocked, .en))
    }

    func testVerbsLocalised() {
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .codepetCanDo, .vi), "Bắt đầu")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsApproval, .vi), "Duyệt")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsYou, .vi), "Cần bạn")
    }

    // done / blocked render as PLAIN TEXT on web, never a pill — so they get a quiet label
    // and no verb. Everything else is nil here (it has a chip instead).
    func testQuietLabelsOnlyForDoneAndBlocked() {
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .done, lang: .en), "Done")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .blocked, lang: .en), "Needs earlier steps")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .done, lang: .vi), "Xong")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .blocked, lang: .vi), "Cần bước trước")
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .codepetCanDo, lang: .en))
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .needsYou, lang: .en))
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .needsApproval, lang: .en))
    }

    // Web shows the small deliverable/tray marker ONLY on locked cards.
    func testTrayMarkerOnlyOnBlocked() {
        XCTAssertTrue(RoadmapBoardCopy.showsTrayMarker(.blocked))
        for s in [TaskStatus.done, .codepetCanDo, .needsYou, .needsApproval] {
            XCTAssertFalse(RoadmapBoardCopy.showsTrayMarker(s))
        }
    }

    // The beacon names the FOUNDER (never the companion), and falls back to second person —
    // composed so it reads "You are here", never "You is here".
    func testHerePhrase() {
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "Mona", lang: .en), "Mona is here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: nil, lang: .en), "You are here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "  ", lang: .en), "You are here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "Mona", lang: .vi), "Mona đang ở đây")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: nil, lang: .vi), "Bạn đang ở đây")
    }

    // The nil branches must hold in BOTH languages: a state that renders a verb chip must never
    // also produce a quiet status line. Asserting only in English left a Vietnamese-only
    // regression invisible.
    func testQuietLabelsAreNilInVietnameseToo() {
        for status in [TaskStatus.codepetCanDo, .needsYou, .needsApproval] {
            XCTAssertNil(RoadmapBoardCopy.quietLabel(for: status, lang: .vi))
        }
    }

    // The whitespace-trim fallback is language-independent; pin it in Vietnamese so it stays that way.
    func testHerePhraseWhitespaceFallbackInVietnamese() {
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "   ", lang: .vi), "Bạn đang ở đây")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "\n", lang: .vi), "Bạn đang ở đây")
    }

    func testWaitingOnNamesTheBlockerInBothLanguages() {
        XCTAssertEqual(RoadmapBoardCopy.waitingOn("Talk to 5 users", lang: .en),
                       "Waiting on: Talk to 5 users")
        XCTAssertTrue(RoadmapBoardCopy.waitingOn("Talk to 5 users", lang: .vi)
                        .contains("Talk to 5 users"))
        XCTAssertNotEqual(RoadmapBoardCopy.waitingOn("x", lang: .en),
                          RoadmapBoardCopy.waitingOn("x", lang: .vi))
    }

    func testNotPlannedYetIsNonEmptyAndDistinctPerLanguage() {
        XCTAssertFalse(RoadmapBoardCopy.notPlannedYet(.en).isEmpty)
        XCTAssertFalse(RoadmapBoardCopy.notPlannedYet(.vi).isEmpty)
        XCTAssertNotEqual(RoadmapBoardCopy.notPlannedYet(.en), RoadmapBoardCopy.notPlannedYet(.vi))
    }

    // MARK: node panel copy

    /// Every phase gets its own sentence, and the sentence names the phase — so the panel can
    /// never show a Foundation contract on a Build card.
    func testBecomesTrueIsDistinctPerPhaseAndNamesThePhase() {
        var seen = Set<String>()
        for phase in RoadmapPhase.allCases {
            let en = RoadmapBoardCopy.becomesTrue(phase, .en)
            XCTAssertFalse(en.isEmpty)
            XCTAssertTrue(en.contains(phase.label(.en)), "\(phase) sentence must name its phase")
            XCTAssertTrue(seen.insert(en).inserted, "\(phase) reuses another phase's sentence")
            XCTAssertNotEqual(en, RoadmapBoardCopy.becomesTrue(phase, .vi))
        }
    }

    func testToCompleteIsDistinctPerWho() {
        let does = RoadmapBoardCopy.toComplete(for: .does, .en)
        let draft = RoadmapBoardCopy.toComplete(for: .draft, .en)
        let you = RoadmapBoardCopy.toComplete(for: .you, .en)
        XCTAssertEqual(Set([does, draft, you]).count, 3)
        for w in [TaskWho.does, .draft, .you] {
            XCTAssertNotEqual(RoadmapBoardCopy.toComplete(for: w, .en),
                              RoadmapBoardCopy.toComplete(for: w, .vi))
        }
    }

    func testHowToFallbackCoversEveryStatus() {
        for s in [TaskStatus.done, .needsApproval, .blocked, .needsYou, .codepetCanDo] {
            XCTAssertFalse(RoadmapBoardCopy.howToFallback(for: s, .en).isEmpty)
            XCTAssertNotEqual(RoadmapBoardCopy.howToFallback(for: s, .en),
                              RoadmapBoardCopy.howToFallback(for: s, .vi))
        }
    }

    func testPhaseMustSettleNamesThePhase() {
        XCTAssertTrue(RoadmapBoardCopy.phaseMustSettle(.find, .en).contains(RoadmapPhase.find.label(.en)))
        XCTAssertNotEqual(RoadmapBoardCopy.phaseMustSettle(.find, .en),
                          RoadmapBoardCopy.phaseMustSettle(.find, .vi))
    }

    /// The panel's primary button has a label for EVERY status — including the two the card
    /// deliberately leaves chip-less (done, blocked), which is exactly why `verb(for:)` can't
    /// serve the panel on its own.
    func testPanelActionLabelCoversEveryStatusIncludingDoneAndBlocked() {
        for s in [TaskStatus.done, .needsApproval, .blocked, .needsYou, .codepetCanDo] {
            XCTAssertFalse(RoadmapBoardCopy.panelActionLabel(for: s, .en).isEmpty)
            XCTAssertNotEqual(RoadmapBoardCopy.panelActionLabel(for: s, .en),
                              RoadmapBoardCopy.panelActionLabel(for: s, .vi))
        }
        XCTAssertNil(RoadmapBoardCopy.verb(for: .blocked, .en))   // the gap being covered
        XCTAssertNil(RoadmapBoardCopy.verb(for: .done, .en))
    }

    func testMarkCompleteAndInProgressStringsAreBilingual() {
        for pair in [(RoadmapBoardCopy.markComplete(.en), RoadmapBoardCopy.markComplete(.vi)),
                     (RoadmapBoardCopy.markNotDone(.en), RoadmapBoardCopy.markNotDone(.vi)),
                     (RoadmapBoardCopy.inProgress(.en), RoadmapBoardCopy.inProgress(.vi))] {
            XCTAssertFalse(pair.0.isEmpty)
            XCTAssertFalse(pair.1.isEmpty)
            XCTAssertNotEqual(pair.0, pair.1)
        }
        XCTAssertNotEqual(RoadmapBoardCopy.markComplete(.en), RoadmapBoardCopy.markNotDone(.en))
    }

    /// The reason is a leverage signal, so the unlock count has to appear — and zero gets its
    /// own phrasing rather than "unlocks 0 later steps".
    func testSuggestionReasonCarriesDeptAndUnlockCount() {
        let two = RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 2, lang: .en)
        XCTAssertTrue(two.contains("Design"))
        XCTAssertTrue(two.contains("2"))
        let one = RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 1, lang: .en)
        XCTAssertTrue(one.contains("1"))
        XCTAssertFalse(one.contains("steps"), "singular for one unlock")
        let none = RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 0, lang: .en)
        XCTAssertFalse(none.contains("0"))
        // A dept-less legacy task still gets a readable prefix.
        XCTAssertFalse(RoadmapBoardCopy.suggestionReason(dept: nil, unlockCount: 1, lang: .en).isEmpty)
        XCTAssertNotEqual(two, RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 2, lang: .vi))
    }
}
