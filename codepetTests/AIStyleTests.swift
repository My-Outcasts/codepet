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
        XCTAssertNotEqual(warmer.promptFragment(), cooler.promptFragment())
        XCTAssertNotNil(warmer.promptFragment())
        XCTAssertNotNil(cooler.promptFragment())
    }

    func test_emojiMoreOverridesTheHardcodedProhibition() {
        var s = AIStyle(); s.emoji = .more
        XCTAssertTrue(s.promptFragment()!.lowercased().contains("emoji"))
    }

    func test_customInstructionsComeLastSoTheyWin() {
        var s = AIStyle()
        s.warmth = .more
        s.customInstructions = "Always name the file path."
        let f = s.promptFragment()!
        XCTAssertTrue(f.hasSuffix("Always name the file path."), f)
    }

    func test_blankTextIsNotAFragment() {
        var s = AIStyle(); s.customInstructions = "   \n "
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
}
