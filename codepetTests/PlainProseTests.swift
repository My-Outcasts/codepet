import XCTest
@testable import codepet

final class PlainProseTests: XCTestCase {

    /// The exact string the Library was showing verbatim in its preview.
    func test_stripsTheMarkersTheLibraryWasLeaking() {
        let raw = "A calm, confident visual direction. **Palette** — one ink (`#1f1b15`), one accent (a violet, `#7c3aed`)."
        let out = PlainProse.strip(raw)
        XCTAssertFalse(out.contains("*"), out)
        XCTAssertFalse(out.contains("`"), out)
        XCTAssertTrue(out.contains("Palette"), out)
        XCTAssertTrue(out.contains("#1f1b15"), "the colour itself is content and must survive")
    }

    func test_dropsLeadingBlockMarkers() {
        XCTAssertEqual(PlainProse.strip("## Pricing"), "Pricing")
        XCTAssertEqual(PlainProse.strip("> a quote"), "a quote")
        XCTAssertEqual(PlainProse.strip("- a bullet"), "a bullet")
        XCTAssertEqual(PlainProse.strip("  1. numbered"), "numbered")
    }

    /// A hyphen inside a sentence is not a bullet and must not be eaten — the pricing
    /// body reads "credits, not a seat/day cap - Trial — 7 days".
    func test_keepsAMidSentenceHyphen() {
        XCTAssertEqual(PlainProse.strip("credits - not a cap"), "credits - not a cap")
    }

    func test_keepsLinkTextAndDropsTheUrl() {
        XCTAssertEqual(PlainProse.strip("see [the plan](https://x.com/y)"), "see the plan")
    }

    /// The Library joins the first two lines of the body; the strip must leave one
    /// readable line rather than a gap where the newline was.
    func test_collapsesNewlinesIntoOneLine() {
        XCTAssertEqual(PlainProse.strip("**Model**\n\ncredits, not seats"), "Model credits, not seats")
    }

    func test_plainProseIsUnchanged() {
        let plain = "Everything Codepet has shipped or drafted."
        XCTAssertEqual(PlainProse.strip(plain), plain)
    }

    func test_emptyAndWhitespaceOnly() {
        XCTAssertEqual(PlainProse.strip(""), "")
        XCTAssertEqual(PlainProse.strip("   \n  "), "")
    }
}
