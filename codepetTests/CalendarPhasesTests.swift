import XCTest
@testable import codepet

/// CP-002 E1: a calendar is a plan in phases. A legacy two-week calendar keeps every field it
/// had — day as `when`, kind as `format` (founder decision, 30 Sep) — and the new fields are
/// shown only when an item has them.
final class CalendarPhasesTests: XCTestCase {

    private func decode(_ payload: String) throws -> CalendarPayload {
        let json = #"{"id":"c","kind":"calendar","title":"T","body":"b","payload":"# + payload + "}"
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        return try XCTUnwrap(d.payload?.calendar, "no calendar decoded")
    }

    func testALegacyWeekLiftsIntoAPhaseWithNothingLost() throws {
        let c = try decode(#"{"weeks":[{"label":"Week 1","items":[{"day":"Mon","kind":"thread","body":"Why"}]}]}"#)
        XCTAssertEqual(c.phases, [CalendarPhase(label: "Week 1", items: [CalendarItem(when: "Mon", format: "thread", body: "Why")])])
    }

    func testTheNewShapeDecodes() throws {
        let c = try decode(#"{"phases":[{"label":"Five days out","from":"T-5","to":"T-3","items":[{"when":"T-5","format":"verify","channel":"App Store","owner":"Engineering","body":"Deletion deletes"}]}]}"#)
        XCTAssertEqual(c.phases.first?.span, "T-5 → T-3")
        XCTAssertEqual(c.phases.first?.items.first?.tags, "T-5 · verify · App Store · Engineering")
    }

    func testSpanAndTagsSkipWhatIsMissing() {
        XCTAssertEqual(CalendarPhase(label: "a", from: "T-0", to: "T-0", items: []).span, "T-0")
        XCTAssertEqual(CalendarPhase(label: "a", from: "", to: "Day 14", items: []).span, "Day 14")
        XCTAssertEqual(CalendarPhase(label: "a", items: []).span, "")
        XCTAssertEqual(CalendarItem(when: "Mon", format: "", body: "b").tags, "Mon")
    }

    /// A re-saved legacy calendar is written as phases, and reads back identical.
    func testALegacyCalendarMigratesOnSave() throws {
        let c = try decode(#"{"weeks":[{"label":"Week 1","items":[{"day":"Mon","kind":"thread","body":"Why"}]}]}"#)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        XCTAssertEqual(Array(obj.keys), ["phases"])
        let item = try XCTUnwrap(((obj["phases"] as? [[String: Any]])?.first?["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(item.keys), ["when", "format", "body"], "empty channel/owner are not written")
        XCTAssertEqual(try JSONDecoder().decode(CalendarPayload.self, from: JSONEncoder().encode(c)), c)
    }

    func testANonCalendarPayloadGrowsNoCalendar() throws {
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(#"{"id":"d","kind":"doc","title":"T","body":"b","payload":{"call":"c","sections":[{"h":"h","p":"p"}]}}"#.utf8))
        XCTAssertNil(d.payload?.calendar)
    }

    func testCopyAndMarkdownCarrySpanAndTags() throws {
        let c = try decode(#"{"phases":[{"label":"Ship day","from":"T-0","to":"","items":[{"when":"Morning","format":"ship","owner":"you","body":"Ship early"}]}]}"#)
        XCTAssertEqual(CalendarViewer.copyText(c), "Ship day (T-0)\nMorning · ship · you — Ship early")
        let d = Deliverable(kind: .calendar, title: "Launch", body: "b", payload: DeliverablePayload(calendar: c))
        let md = DeliverableMarkdown.render(d, dept: "Ops", instruction: "x")
        XCTAssertTrue(md.contains("## Ship day (T-0)\n\n- **Morning · ship · you:** Ship early"), md)
    }

    func testTheIcsDescriptionCarriesChannelAndOwner() throws {
        let c = try decode(#"{"phases":[{"label":"Ship day","from":"","to":"","items":[{"when":"Mon","format":"post","channel":"X","owner":"Marketing","body":"Launch thread"}]}]}"#)
        let d = Deliverable(kind: .calendar, title: "Launch", body: "b", payload: DeliverablePayload(calendar: c))
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        // RFC 5545 folds lines at 75 octets with CRLF + space; unfold before reading a property.
        let unfolded = ics.replacingOccurrences(of: "\r\n ", with: "")
        XCTAssertTrue(unfolded.contains("Ship day · Mon · post · X · Marketing — day is relative to export"), unfolded)
    }
}
