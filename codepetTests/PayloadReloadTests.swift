import XCTest
@testable import codepet

/// A filed calendar, sheet, site or screens deliverable must survive a save and a reload.
///
/// It did not. The server sends these four kinds FLAT (`{"price": …}`), and `DeliverablePayload`
/// decodes them from the flat container. But its synthesized encoder writes each one NESTED
/// under its own key (`{"sheet": {"price": …}}`), which is the form `CompanyData.saveLibrary`
/// puts in Firestore, and the flat decode found nothing there. So on the next load the
/// payload was gone: a filed landing page fell back to its markdown copy, a pricing model lost
/// its sliders. Everything else in the payload is flat both ways and was never affected.
///
/// Exercised through the real save path (`deliverablesPayload`) and the real load shape
/// (`[Deliverable]` under `library`), not a hand-written nested JSON, so a change to either
/// end is what this catches.
final class PayloadReloadTests: XCTestCase {

    private func reload(_ d: Deliverable) throws -> Deliverable {
        let data = try JSONSerialization.data(withJSONObject: CompanyData.deliverablesPayload([d]))
        struct Doc: Decodable { let library: [Deliverable] }
        return try XCTUnwrap(JSONDecoder().decode(Doc.self, from: data).library.first)
    }

    private func wire(_ kind: String, _ payload: String) throws -> Deliverable {
        let json = #"{"id":"d","kind":""# + kind + #"","title":"T","body":"md","payload":"# + payload + "}"
        return try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
    }

    func testASheetSurvivesAReload() throws {
        let d = try wire("sheet", #"{"price":{"val":9,"min":1,"max":50,"step":1},"waitlist":{"val":1000,"min":0,"max":5000,"step":50},"conversion":{"val":5,"min":1,"max":30,"step":1},"churn":{"val":4,"min":1,"max":20,"step":1},"summary":"x"}"#)
        XCTAssertNotNil(d.payload?.sheet, "precondition: the wire form decodes")
        XCTAssertEqual(try reload(d).payload?.sheet, d.payload?.sheet)
    }

    func testACalendarSurvivesAReload() throws {
        let d = try wire("calendar", #"{"weeks":[{"label":"Week 1","items":[{"day":"Mon","kind":"Thread","body":"Post"}]}]}"#)
        XCTAssertNotNil(d.payload?.calendar)
        XCTAssertEqual(try reload(d).payload?.calendar, d.payload?.calendar)
    }

    func testASiteSurvivesAReload() throws {
        let d = try wire("site", #"{"title":"T","brand":"B","headline":"H","ctaPrimary":"Go","finalTitle":"F","finalCta":"Go","steps":[{"h":"a","p":"b"}]}"#)
        XCTAssertNotNil(d.payload?.site)
        XCTAssertEqual(try reload(d).payload?.site, d.payload?.site)
    }

    func testScreensSurviveAReload() throws {
        let d = try wire("screens", #"{"screens":[{"name":"Connect","time":"0:00","title":"T","art":"connect"}]}"#)
        XCTAssertNotNil(d.payload?.screens)
        XCTAssertEqual(try reload(d).payload?.screens, d.payload?.screens)
    }

    /// The flat fields were never broken; pinned so the fix cannot regress them.
    func testFlatPayloadsStillSurviveAReload() throws {
        let d = try wire("doc", #"{"call":"c","sections":[{"h":"h","p":"p"}],"next":["n"],"rules_out":["r"]}"#)
        XCTAssertEqual(try reload(d).payload, d.payload)
    }

    /// Saved twice must equal saved once — a reload feeds the next save.
    func testSavingAReloadedDeliverableIsStable() throws {
        let d = try wire("site", #"{"title":"T","brand":"B","headline":"H","ctaPrimary":"Go","finalTitle":"F","finalCta":"Go"}"#)
        XCTAssertEqual(try reload(try reload(d)).payload, d.payload)
    }
}
