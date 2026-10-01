import XCTest
@testable import codepet

/// CP-002 E3: a screen's `art` is a description, not one of three values. The three keep their
/// symbol art; anything else is shown as a brief; nothing draws nothing (founder decision, 30 Sep).
final class ScreenArtTests: XCTestCase {

    func testTheThreeKeepTheirSymbols() {
        XCTAssertEqual(ScreenArt("connect"), .symbols(primary: "link", secondary: "person.2"))
        XCTAssertEqual(ScreenArt("session"), .symbols(primary: "bubble.left.and.bubble.right", secondary: "sparkles"))
        XCTAssertEqual(ScreenArt("recap"), .symbols(primary: "checkmark.seal", secondary: "chart.bar"))
    }

    func testAnythingElseIsABriefAsWritten() {
        XCTAssertEqual(ScreenArt("a week of check-ins filling a grid"), .brief("a week of check-ins filling a grid"))
        XCTAssertEqual(ScreenArt("  a chart  "), .brief("a chart"))
    }

    /// The old fallback drew a dashed rectangle with a question mark — a broken-image look.
    func testNoArtDrawsNothing() {
        XCTAssertEqual(ScreenArt(""), .none)
        XCTAssertEqual(ScreenArt("   "), .none)
    }

    func testAScreenMayOmitArt() throws {
        let json = #"{"id":"s","kind":"screens","title":"T","body":"b","payload":{"screens":[{"name":"One","time":"0:00","title":"Hello"}]}}"#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(d.payload?.screens?.screens.first?.art, "")
        let md = DeliverableMarkdown.render(d, dept: "Design", instruction: "x")
        XCTAssertFalse(md.contains("Art:"), "no art, no empty Art line: \(md)")
    }

    func testMoreThanThreeScreensDecode() throws {
        let screen = #"{"name":"S","time":"0:00","title":"T","art":"a chart"}"#
        let json = #"{"id":"s","kind":"screens","title":"T","body":"b","payload":{"screens":["# + Array(repeating: screen, count: 6).joined(separator: ",") + "]}}"
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(d.payload?.screens?.screens.count, 6)
    }
}
