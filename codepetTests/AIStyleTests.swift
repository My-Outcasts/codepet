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
