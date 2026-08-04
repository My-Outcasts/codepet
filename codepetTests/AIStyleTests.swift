import XCTest
@testable import codepet

final class AIStyleTests: XCTestCase {
    func test_untouchedStyleAddsNothingToThePrompt() {
        XCTAssertNil(AIStyle().promptFragment())
    }

    func test_baseToneEmitsOneLine() {
        var s = AIStyle(); s.baseTone = .direct
        let f = s.promptFragment()
        XCTAssertNotNil(f)
        XCTAssertTrue(f!.contains("blunt"), f!)
    }

    func test_eachLevelEmitsItsOwnDirection() {
        var warmer = AIStyle(); warmer.warmth = .more
        var cooler = AIStyle(); cooler.warmth = .less
        XCTAssertEqual(warmer.promptFragment(), "Warmer than usual: acknowledge how the work is going.")
        XCTAssertEqual(cooler.promptFragment(), "Cooler than usual: no pleasantries, no check-ins.")

        var moreEnthused = AIStyle(); moreEnthused.enthusiasm = .more
        var lessEnthused = AIStyle(); lessEnthused.enthusiasm = .less
        XCTAssertEqual(moreEnthused.promptFragment(), "Show more enthusiasm when something is working.")
        XCTAssertEqual(lessEnthused.promptFragment(), "Stay level. No exclamation marks, no celebration.")
    }

    func test_emojiMoreOverridesTheHardcodedProhibition() {
        var s = AIStyle(); s.emoji = .more
        XCTAssertTrue(s.promptFragment()!.lowercased().contains("emoji"))
    }

    func test_customInstructionsComeLastSoTheyWin() {
        var s = AIStyle()
        s.warmth = .more
        s.role = "solo founder"
        s.moreAboutYou = "ships on weekends"
        s.customInstructions = "Always name the file path."
        let f = s.promptFragment()!
        XCTAssertTrue(f.hasSuffix("Always name the file path."), f)
    }

    func test_blankTextIsNotAFragment() {
        var s = AIStyle(); s.customInstructions = "   \n "
        XCTAssertNil(s.promptFragment())
    }

    func test_blankRoleIsNotAFragment() {
        var s = AIStyle(); s.role = "   \n "
        XCTAssertNil(s.promptFragment())
    }

    func test_blankMoreAboutYouIsNotAFragment() {
        var s = AIStyle(); s.moreAboutYou = "   \n "
        XCTAssertNil(s.promptFragment())
    }

    func test_aboutYouTravelsWithTheStyle() {
        var s = AIStyle(); s.role = "solo founder"; s.moreAboutYou = "ships on weekends"
        let f = s.promptFragment()!
        XCTAssertTrue(f.contains("solo founder"))
        XCTAssertTrue(f.contains("ships on weekends"))
    }

    func test_roundTripsThroughJSON() throws {
        var p = FounderPrefs()
        p.style.baseTone = .analytical
        p.memoryEnabled = false
        p.notifications["sessionNudges"] = .off
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(FounderPrefs.self, from: data), p)
    }

    func test_defaultsAreTheOldBehaviour() {
        let p = FounderPrefs()
        XCTAssertTrue(p.memoryEnabled)
        XCTAssertNil(p.style.promptFragment())
        XCTAssertTrue(p.notifications.isEmpty)
    }

    // MARK: - Budget: clipping must never cost the founder their custom instruction

    /// Regression. `customInstructions` is appended LAST so an explicit instruction wins by
    /// recency — but the 2000-char clip in `styleBlock` (functions/src/companyChatCore.ts)
    /// applies to the JOINED fragment, so a long `moreAboutYou` used to push the custom
    /// instruction off the end of what the server forwards. The field the founder filled in
    /// most deliberately was the one silently discarded.
    func test_aLongMoreAboutYouCannotClipTheCustomInstructionOut() {
        var s = AIStyle()
        s.warmth = .more
        s.role = String(repeating: "r", count: 4_000)
        s.moreAboutYou = String(repeating: "m", count: 8_000)
        s.customInstructions = "Always name the file path."
        let f = s.promptFragment()!

        // Exactly what reaches the model: styleBlock clips the joined fragment to 2000.
        let asSent = String(f.prefix(AIStyle.fragmentBudget))
        XCTAssertTrue(asSent.contains("Always name the file path."),
                      "the founder's explicit instruction has to survive the server's clip")
        // Order is unchanged — it still wins by being last.
        XCTAssertTrue(f.hasSuffix("Always name the file path."), f.suffix(80).description)
        // ...and the long field is what paid for it.
        XCTAssertTrue(f.contains(String(repeating: "m", count: 100)))
    }

    /// The property that makes the clip harmless rather than merely unlikely: no combination
    /// of knobs and free text can produce a fragment the server would have to cut at all.
    /// A future knob line long enough to break this fails here rather than in a prompt.
    func test_noStyleAtAllCanExceedTheServerBudget() {
        let long = String(repeating: "x", count: 10_000)
        for tone in AIStyle.BaseTone.allCases {
            for warmth in AIStyle.Level.allCases {
                for enthusiasm in AIStyle.Level.allCases {
                    for emoji in AIStyle.Level.allCases {
                        var s = AIStyle()
                        s.baseTone = tone
                        s.warmth = warmth
                        s.enthusiasm = enthusiasm
                        s.emoji = emoji
                        s.role = long
                        s.moreAboutYou = long
                        s.customInstructions = long
                        let f = s.promptFragment()!
                        // UTF-16, because that is what styleBlock's slice counts.
                        XCTAssertLessThanOrEqual(
                            f.utf16.count, AIStyle.fragmentBudget,
                            "\(tone)/\(warmth)/\(enthusiasm)/\(emoji) overflows the budget")
                    }
                }
            }
        }
    }

    /// An emoji is one `Character` but two UTF-16 code units, and `styleBlock` counts the
    /// latter — so bounding on `count` would still overflow the server's clip.
    func test_emojiHeavyTextIsBoundedInTheUnitsTheServerCounts() {
        var s = AIStyle()
        s.role = String(repeating: "🙂", count: 5_000)
        s.moreAboutYou = String(repeating: "🙂", count: 5_000)
        s.customInstructions = String(repeating: "🙂", count: 5_000) + " Ship it."
        let f = s.promptFragment()!
        XCTAssertLessThanOrEqual(f.utf16.count, AIStyle.fragmentBudget)
    }

    /// Bounding a field must not manufacture a fragment out of nothing, and must not split a
    /// grapheme: the all-defaults `nil` and the blank-text cases above still hold.
    func test_boundingDoesNotSplitAGraphemeOrInventAFragment() {
        XCTAssertNil(AIStyle().promptFragment())
        // Odd limit against 2-unit graphemes: the last one is dropped whole, never halved.
        let bounded = AIStyle.bounded(String(repeating: "🙂", count: 4), to: 5)
        XCTAssertEqual(bounded, "🙂🙂")
        XCTAssertEqual(AIStyle.bounded("  hi  ", to: 100), "hi")
        XCTAssertEqual(AIStyle.bounded("hello world", to: 6), "hello")
    }

    // MARK: - F1: absent keys must decode as defaults, not throw

    func test_absentKeysDecodeAIStyleAsAllDefaults() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIStyle.self, from: data)
        XCTAssertEqual(decoded, AIStyle())
        XCTAssertNil(decoded.promptFragment())
    }

    func test_absentKeysDecodeFounderPrefsAsAllDefaults() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FounderPrefs.self, from: data)
        XCTAssertEqual(decoded, FounderPrefs())
        // The exact bug this guards: a synthesized decoder throws keyNotFound on `{}`
        // rather than falling back to the property's declared default of `true`.
        XCTAssertTrue(decoded.memoryEnabled)
    }

    func test_partialPayloadFillsEverythingElseWithDefaults() throws {
        let data = #"{"baseTone":"direct"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIStyle.self, from: data)
        var expected = AIStyle()
        expected.baseTone = .direct
        XCTAssertEqual(decoded, expected)
        XCTAssertEqual(decoded.warmth, .default)
        XCTAssertEqual(decoded.enthusiasm, .default)
        XCTAssertEqual(decoded.emoji, .default)
        XCTAssertEqual(decoded.customInstructions, "")
        XCTAssertEqual(decoded.role, "")
        XCTAssertEqual(decoded.moreAboutYou, "")
    }
}
