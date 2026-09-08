import XCTest
@testable import codepet

final class ChatThinkingLabelTests: XCTestCase {

    // MARK: - The named-work line, which does NOT vary

    func testNamedTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "positioning brief", language: .en),
                       "Drafting positioning brief…")
    }
    func testNamedTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "positioning brief", language: .vi),
                       "Đang soạn positioning brief…")
    }
    /// A title exists, so the phrase set must not be reached no matter which variant is in
    /// play — the founder reads this line to know WHICH deliverable is being written.
    func testANamedTaskIgnoresTheVariant() {
        for variant in 0..<ChatThinkingLabel.phraseCount {
            XCTAssertEqual(
                ChatThinkingLabel.text(taskTitle: "positioning brief", language: .en, variant: variant),
                "Drafting positioning brief…",
                "variant \(variant) changed a named-task label")
        }
    }

    // MARK: - The generic line, which does

    /// Index 0 is the calm anchor, and `text`'s default variant is 0 — so a caller that does
    /// not rotate still gets the line this label shipped with.
    func testTheDefaultVariantIsStillThePlainAnchor() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .en), "Working on it…")
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .vi), "Đang xử lý…")
    }

    func testBlankTitleTreatedAsNone() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "   ", language: .en), "Working on it…")
    }

    /// The whole point of the change: the set must actually hold different strings. A set
    /// that had collapsed to one repeated phrase would satisfy every other test here.
    func testThePhrasesAreDistinctAndPlural() {
        for lang in [AppLanguage.en, .vi] {
            let set = ChatThinkingLabel.phrases(lang)
            XCTAssertGreaterThan(set.count, 1, "\(lang) has nothing to rotate through")
            XCTAssertEqual(Set(set).count, set.count, "\(lang) repeats a phrase inside the set")
        }
    }

    /// Both languages must be the same length: the founder can switch language while a reply
    /// is in flight, and the variant already rolled has to stay a valid index in the other.
    func testBothLanguagesCarryTheSameNumberOfPhrases() {
        XCTAssertEqual(ChatThinkingLabel.phrases(.en).count,
                       ChatThinkingLabel.phrases(.vi).count)
    }

    /// Every variant resolves to a real phrase in both languages — no index escapes the set.
    func testEveryVariantResolvesInBothLanguages() {
        for lang in [AppLanguage.en, .vi] {
            let set = ChatThinkingLabel.phrases(lang)
            for variant in 0..<ChatThinkingLabel.phraseCount {
                XCTAssertTrue(set.contains(ChatThinkingLabel.text(taskTitle: nil,
                                                                  language: lang,
                                                                  variant: variant)))
            }
        }
    }

    /// An out-of-range or negative variant must fold back into the set rather than trap.
    /// `-1` is the one that matters: Swift's `%` keeps the sign, so a naive `variant % count`
    /// would index at -1 and crash the dock mid-stream.
    func testAnOutOfRangeVariantFoldsInsteadOfTrapping() {
        let set = ChatThinkingLabel.phrases(.en)
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .en, variant: set.count),
                       set[0])
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .en, variant: -1),
                       set[set.count - 1])
        // `Int.min` is the case `abs()` would trap on. Traced: `Int.min % 8 == 0` (Int.min
        // is -2^63 and 8 divides it), so it folds to index 0.
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .en, variant: Int.min),
                       set[0])
    }

    // MARK: - The rotation rule

    /// Hand-traced against the implementation, count = 8:
    ///   previous 3, roll 0 → choice 0, 0 < 3 → 0
    ///   previous 3, roll 3 → choice 3, not < 3 → 4   (the excluded index is stepped over)
    ///   previous 3, roll 6 → choice 6, not < 3 → 7   (the last index stays reachable)
    ///   previous 0, roll 0 → choice 0, not < 0 → 1
    ///   previous 7, roll 6 → choice 6, 6 < 7 → 6
    func testNextIndexStepsOverThePreviousPhrase() {
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 3, count: 8, roll: 0), 0)
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 3, count: 8, roll: 3), 4)
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 3, count: 8, roll: 6), 7)
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 0, count: 8, roll: 0), 1)
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 7, count: 8, roll: 6), 6)
    }

    /// The property the founder actually sees: no phrase twice running, for EVERY previous
    /// and every roll. Exhaustive over both, so a rule that merely usually differs is red.
    func testNoPhraseEverRepeatsBackToBack() {
        let count = ChatThinkingLabel.phraseCount
        for previous in 0..<count {
            for roll in -count...(count * 3) {
                let next = ChatThinkingLabel.nextIndex(previous: previous, count: count, roll: roll)
                XCTAssertNotEqual(next, previous, "roll \(roll) repeated phrase \(previous)")
                XCTAssertTrue((0..<count).contains(next), "roll \(roll) escaped the set: \(next)")
            }
        }
    }

    /// Every phrase but the excluded one must be reachable — a rule that never picked, say,
    /// the last phrase would pass `testNoPhraseEverRepeatsBackToBack` while quietly shrinking
    /// the set the founder sees.
    func testEveryOtherPhraseIsReachableFromAnyPrevious() {
        let count = ChatThinkingLabel.phraseCount
        for previous in 0..<count {
            let reached = Set((0..<(count - 1)).map {
                ChatThinkingLabel.nextIndex(previous: previous, count: count, roll: $0)
            })
            XCTAssertEqual(reached, Set(0..<count).subtracting([previous]),
                           "from \(previous) the rotation cannot reach every other phrase")
        }
    }

    /// No previous phrase (first turn of a session) → the whole set is in play, including
    /// the last index, which an off-by-one in the exclusion branch would drop.
    func testWithNoPreviousTheWholeSetIsInPlay() {
        let count = ChatThinkingLabel.phraseCount
        let reached = Set((0..<count).map {
            ChatThinkingLabel.nextIndex(previous: nil, count: count, roll: $0)
        })
        XCTAssertEqual(reached, Set(0..<count))
    }

    /// A `previous` that is not an index into the set must be treated as "no previous",
    /// not shifted around: shifting would make index 0 unreachable and, for a large
    /// `previous`, drop the last phrase too.
    func testAPreviousOutsideTheSetIsTreatedAsNone() {
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 99, count: 8, roll: 0), 0)
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: -1, count: 8, roll: 5), 5)
    }

    /// Degenerate set: one phrase and nothing to alternate with. It must return the only
    /// valid index rather than divide by `count - 1 == 0`.
    func testASingletonSetReturnsItsOnlyIndex() {
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: 0, count: 1, roll: 7), 0)
        XCTAssertEqual(ChatThinkingLabel.nextIndex(previous: nil, count: 1, roll: 7), 0)
    }

    /// `rolled()` is the impure convenience the view uses. It must honour the same rule
    /// against whatever was last on screen.
    func testRolledNeverReturnsTheLastShownPhrase() {
        let restore = ChatThinkingLabel.lastShown
        defer { ChatThinkingLabel.lastShown = restore }
        for shown in 0..<ChatThinkingLabel.phraseCount {
            ChatThinkingLabel.lastShown = shown
            for _ in 0..<50 {
                XCTAssertNotEqual(ChatThinkingLabel.rolled(), shown)
            }
        }
    }
}

// MARK: - Naming the pet (7 Sep — the row lost its orb, so the words carry the identity)

extension ChatThinkingLabelTests {
    func testPetAndTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Luna", taskTitle: "the brand direction",
                                              language: .en),
                       "Luna is drafting the brand direction…")
    }
    func testPetAndTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Luna", taskTitle: "the brand direction",
                                              language: .vi),
                       "Luna đang soạn the brand direction…")
    }
    func testPetWithNoTask() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Crash", taskTitle: nil, language: .en),
                       "Crash is on it…")
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Crash", taskTitle: nil, language: .vi),
                       "Crash đang làm…")
    }

    /// **The fallbacks are the point.** An unknown companion id resolves to nil, and the row
    /// must then read exactly as it did before rather than asserting a specialist that is not
    /// working. These are the two cases that would let the label lie.
    func testBlankPetFallsBackToTheUnnamedCopy() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "   ", taskTitle: nil, language: .en),
                       "Working on it…")
        XCTAssertEqual(ChatThinkingLabel.text(petName: nil, taskTitle: "positioning brief",
                                              language: .en),
                       "Drafting positioning brief…")
    }
}

// MARK: - The pet-named rotation (the two 7 Sep calls, merged)

extension ChatThinkingLabelTests {

    /// One rolled variant has to be a valid index in ALL FOUR sets: the founder can change
    /// language, or a department handoff can land, while a reply is in flight. Referenced by
    /// `ChatThinkingLabel.phraseCount`'s comment.
    func testAllFourPhraseSetsAreTheSameLength() {
        let n = ChatThinkingLabel.phraseCount
        XCTAssertEqual(ChatThinkingLabel.phrases(.en).count, n)
        XCTAssertEqual(ChatThinkingLabel.phrases(.vi).count, n)
        XCTAssertEqual(ChatThinkingLabel.petPhrases(.en).count, n)
        XCTAssertEqual(ChatThinkingLabel.petPhrases(.vi).count, n)
    }

    /// The pet set must rotate too, and must be distinct — a set that had collapsed to one
    /// repeated template would satisfy every naming test above.
    func testThePetPhrasesAreDistinctAndPlural() {
        for lang in [AppLanguage.en, .vi] {
            let set = ChatThinkingLabel.petPhrases(lang)
            XCTAssertGreaterThan(set.count, 1, "\(lang) pet set has nothing to rotate through")
            XCTAssertEqual(Set(set).count, set.count, "\(lang) repeats a pet template")
        }
    }

    /// **Every template must actually carry the name.** A template that lost its token would
    /// render a pet-attributed row that names nobody — the exact failure the orb removal was
    /// meant to end — and no other test here would notice.
    func testEveryPetTemplateNamesThePet() {
        for lang in [AppLanguage.en, .vi] {
            for (i, template) in ChatThinkingLabel.petPhrases(lang).enumerated() {
                XCTAssertTrue(template.contains(ChatThinkingLabel.nameToken),
                              "\(lang) pet template \(i) has no name token: \(template)")
            }
        }
    }

    /// And the token must be gone by the time it reaches the founder.
    func testEveryVariantRendersThePetNameAndLeavesNoToken() {
        for lang in [AppLanguage.en, .vi] {
            for variant in 0..<ChatThinkingLabel.phraseCount {
                let out = ChatThinkingLabel.text(petName: "Nova", taskTitle: nil,
                                                 language: lang, variant: variant)
                XCTAssertTrue(out.contains("Nova"), "variant \(variant) (\(lang)) lost the name: \(out)")
                XCTAssertFalse(out.contains(ChatThinkingLabel.nameToken),
                               "variant \(variant) (\(lang)) leaked the token: \(out)")
            }
        }
    }

    /// Variant 0 is the anchor in the pet set too, so the default reproduces the copy this
    /// row shipped with this morning, byte for byte. Traced: `petPhrases(.en)[0]` is
    /// "{pet} is on it…", so substituting gives "Nova is on it…".
    func testTheAnchorVariantReproducesTheShippedPetCopy() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Nova", taskTitle: nil, language: .en),
                       "Nova is on it…")
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Nova", taskTitle: nil, language: .vi),
                       "Nova đang làm…")
    }

    /// A pet AND a real title is the one case that names actual work, so it must stay
    /// literal at every variant — same rule as the unnamed titled case.
    func testAPetNamedTaskIgnoresTheVariant() {
        for variant in 0..<ChatThinkingLabel.phraseCount {
            XCTAssertEqual(
                ChatThinkingLabel.text(petName: "Luna", taskTitle: "the brand direction",
                                       language: .en, variant: variant),
                "Luna is drafting the brand direction…",
                "variant \(variant) changed a pet-named task label")
        }
    }

    /// The two title-less cases share one variant index, which is what lets a handoff
    /// landing mid-reply keep the register instead of jumping to an unrelated line: at any
    /// given variant the unnamed and pet-named phrases are the same phrase.
    func testTheUnnamedAndPetNamedSetsStayInStepAtEveryVariant() {
        for variant in 0..<ChatThinkingLabel.phraseCount {
            let bare = ChatThinkingLabel.text(taskTitle: nil, language: .en, variant: variant)
            let named = ChatThinkingLabel.text(petName: "Nova", taskTitle: nil,
                                               language: .en, variant: variant)
            XCTAssertEqual(bare, ChatThinkingLabel.phrases(.en)[variant])
            XCTAssertEqual(named, ChatThinkingLabel.petPhrases(.en)[variant]
                                    .replacingOccurrences(of: ChatThinkingLabel.nameToken,
                                                          with: "Nova"))
        }
    }
}

// MARK: - Tool activity (8 Sep — a literal line for a tool running mid-turn)

extension ChatThinkingLabelTests {
    func testReadFileActivityWithPetEnglish() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .readFile, target: "mml-book.pdf"),
                                   language: .en),
            "Luna is reading mml-book.pdf…")
    }
    func testReadFileActivityWithPetVietnamese() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .readFile, target: "mml-book.pdf"),
                                   language: .vi),
            "Luna đang đọc mml-book.pdf…")
    }

    func testFetchPageActivityWithPetEnglish() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .fetchPage, target: "web.murror.app/welcome"),
                                   language: .en),
            "Luna is reading web.murror.app/welcome…")
    }
    func testFetchPageActivityWithPetVietnamese() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .fetchPage, target: "web.murror.app/welcome"),
                                   language: .vi),
            "Luna đang đọc web.murror.app/welcome…")
    }

    func testSearchWebActivityWithPetEnglish() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .searchWeb, target: nil),
                                   language: .en),
            "Luna is searching the web…")
    }
    func testSearchWebActivityWithPetVietnamese() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .searchWeb, target: nil),
                                   language: .vi),
            "Luna đang tìm trên web…")
    }

    /// No pet — the same lines without a name, mirroring how `taskTitle` already falls
    /// back (`"Drafting positioning brief…"` with no pet).
    func testActivityFallsBackToUnnamedCopyWithNoPet() {
        XCTAssertEqual(
            ChatThinkingLabel.text(taskTitle: nil,
                                   activity: ChatToolActivity(kind: .readFile, target: "mml-book.pdf"),
                                   language: .en),
            "Reading mml-book.pdf…")
        XCTAssertEqual(
            ChatThinkingLabel.text(taskTitle: nil,
                                   activity: ChatToolActivity(kind: .readFile, target: "mml-book.pdf"),
                                   language: .vi),
            "Đang đọc mml-book.pdf…")
        XCTAssertEqual(
            ChatThinkingLabel.text(taskTitle: nil,
                                   activity: ChatToolActivity(kind: .searchWeb, target: nil),
                                   language: .en),
            "Searching the web…")
        XCTAssertEqual(
            ChatThinkingLabel.text(taskTitle: nil,
                                   activity: ChatToolActivity(kind: .searchWeb, target: nil),
                                   language: .vi),
            "Đang tìm trên web…")
    }

    /// A real activity is exactly as literal as a real task title — it must not vary at
    /// any rotation index, or the founder would see the tool's own name flicker between
    /// unrelated phrases.
    func testActivityIgnoresTheVariant() {
        for variant in 0..<ChatThinkingLabel.phraseCount {
            XCTAssertEqual(
                ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                       activity: ChatToolActivity(kind: .readFile, target: "mml-book.pdf"),
                                       language: .en, variant: variant),
                "Luna is reading mml-book.pdf…",
                "variant \(variant) changed an activity label")
        }
    }

    /// A blank target must not render "Luna is reading …" with nothing after "reading" —
    /// it falls back to plain rotation instead, exactly like a blank task title does.
    func testBlankActivityTargetFallsBackToRotation() {
        XCTAssertEqual(
            ChatThinkingLabel.text(petName: "Luna", taskTitle: nil,
                                   activity: ChatToolActivity(kind: .readFile, target: "   "),
                                   language: .en),
            "Luna is on it…")
    }
}
