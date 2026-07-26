import XCTest
@testable import codepet

final class DeliverablePayloadTests: XCTestCase {
    func testChecklistPayloadRoundTrips() throws {
        let d = Deliverable(kind: .checklist, title: "T", body: "md",
            payload: DeliverablePayload(items: [ChecklistItem(t: "Step", done: false)]))
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.payload?.items?.first?.t, "Step")
    }
    func testLegacyDeliverableWithoutPayloadDecodes() throws {
        let legacy = #"{"id":"x","kind":"post","title":"T","body":"md"}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(legacy.utf8))
        XCTAssertNil(back.payload)
    }
    func testDecodesStructuredPayloadFromCFShape() throws {
        let json = #"{"id":"y","kind":"plan","title":"P","body":"md","payload":{"goal":"g","steps":["a"],"changes":[{"area":"x","edit":"y"}],"verify":[],"risks":"r"}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.goal, "g")
        XCTAssertEqual(back.payload?.changes?.first?.area, "x")
    }

    // MARK: - plan regression (steps collision fix must not break plan)

    func testPlanPayloadStillDecodesStepsAsStringArray_SiteNil() throws {
        let json = #"{"id":"p1","kind":"plan","title":"P","body":"md","payload":{"goal":"g","steps":["a","b"],"changes":[{"area":"x","edit":"y"}],"verify":["v"],"risks":"r"}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.steps, ["a", "b"])
        XCTAssertNil(back.payload?.site)
    }

    // MARK: - calendar

    func testDecodesCalendarPayload() throws {
        let json = #"""
        {"id":"c1","kind":"calendar","title":"C","body":"md","payload":{
            "weeks":[{"label":"Week 1","items":[{"day":"Mon","kind":"post","body":"Ship it"}]}]
        }}
        """#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.calendar?.weeks.first?.label, "Week 1")
        XCTAssertEqual(back.payload?.calendar?.weeks.first?.items.first?.day, "Mon")
        XCTAssertNil(back.payload?.steps)
        XCTAssertNil(back.payload?.site)
        XCTAssertNil(back.payload?.sheet)
        XCTAssertNil(back.payload?.screens)
    }

    // MARK: - sheet

    func testDecodesSheetPayload() throws {
        let json = #"""
        {"id":"s1","kind":"sheet","title":"S","body":"md","payload":{
            "price":{"val":9,"min":0,"max":100,"step":1},
            "waitlist":{"val":50,"min":0,"max":1000,"step":10},
            "conversion":{"val":0.2,"min":0,"max":1,"step":0.01},
            "churn":{"val":0.05,"min":0,"max":1,"step":0.01},
            "summary":"Looks healthy"
        }}
        """#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.sheet?.price.val, 9)
        XCTAssertEqual(back.payload?.sheet?.summary, "Looks healthy")
        XCTAssertNil(back.payload?.site)
        XCTAssertNil(back.payload?.calendar)
        XCTAssertNil(back.payload?.screens)
    }

    // MARK: - site (the steps collision)

    func testDecodesSitePayload_StepsAreObjects_PlanStepsNil() throws {
        let json = #"""
        {"id":"si1","kind":"site","title":"Site","body":"md","payload":{
            "title":"T","brand":"B","kicker":"K","headline":"H","headlineHi":"HH","sub":"Sub",
            "ctaPrimary":"Go","ctaSecondary":"Learn","howEyebrow":"How","howTitle":"How it works",
            "steps":[{"h":"Step 1","p":"Do a thing"}],
            "featEyebrow":"Feat","featTitle":"Features",
            "features":[{"h":"Feature 1","p":"Does a thing"}],
            "quote":"Great","quoteBy":"Someone","finalTitle":"Final","finalSub":"Sub2",
            "finalCta":"Start","accent":"#7B6BD8","footNote":"note"
        }}
        """#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.site?.headline, "H")
        XCTAssertEqual(back.payload?.site?.steps.first?.h, "Step 1")
        XCTAssertEqual(back.payload?.site?.features.first?.p, "Does a thing")
        // The collision: plan's [String] `steps` must NOT populate from a site payload.
        XCTAssertNil(back.payload?.steps)
        XCTAssertNil(back.payload?.calendar)
        XCTAssertNil(back.payload?.sheet)
        XCTAssertNil(back.payload?.screens)
    }

    // MARK: - site soft-field hardening (missing soft field degrades; missing anchor still falls back)

    func testSitePayloadMissingSoftFieldDegradesToEmpty() throws {
        // No `quoteBy` at all (e.g. a site with no testimonial byline). All other
        // required anchor fields are present, so `.site` must still decode.
        let json = #"""
        {"id":"si2","kind":"site","title":"Site","body":"md","payload":{
            "title":"T","brand":"B","headline":"H","ctaPrimary":"Go",
            "finalTitle":"Final","finalCta":"Start",
            "steps":[{"h":"Step 1","p":"Do a thing"}],
            "features":[{"h":"Feature 1","p":"Does a thing"}],
            "quote":"Great"
        }}
        """#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertNotNil(back.payload?.site)
        XCTAssertEqual(back.payload?.site?.title, "T")
        XCTAssertEqual(back.payload?.site?.quoteBy, "")
        XCTAssertEqual(back.payload?.site?.kicker, "")
        XCTAssertEqual(back.payload?.site?.accent, "")
    }

    func testSitePayloadMissingAnchorFieldStaysNil() throws {
        // Missing the REQUIRED anchor field `title` — this must still throw and fall
        // back to nil, proving the steps-collision fix still holds (a PLAN payload has
        // no `title`/`headline` either, so it must not masquerade as a site).
        let json = #"""
        {"id":"si3","kind":"site","title":"Site","body":"md","payload":{
            "brand":"B","headline":"H","ctaPrimary":"Go","finalTitle":"Final","finalCta":"Start"
        }}
        """#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertNil(back.payload?.site)
    }

    // MARK: - screens

    func testDecodesScreensPayload() throws {
        let json = #"""
        {"id":"sc1","kind":"screens","title":"Screens","body":"md","payload":{
            "screens":[{"name":"Connect","time":"0:00","kick":"Kick","title":"Title","sub":"Sub","art":"connect","cta":"Next","note":"Note"}]
        }}
        """#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.screens?.screens.first?.name, "Connect")
        XCTAssertEqual(back.payload?.screens?.screens.first?.art, "connect")
        XCTAssertNil(back.payload?.site)
        XCTAssertNil(back.payload?.steps)
        XCTAssertNil(back.payload?.calendar)
        XCTAssertNil(back.payload?.sheet)
    }

    // MARK: - doc / dms still decode as before

    func testDocPayloadStillDecodes() throws {
        let json = #"{"id":"d1","kind":"doc","title":"D","body":"md","payload":{"call":"Do the thing","sections":[{"h":"Head","p":"Body"}],"next":["follow up"]}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.call, "Do the thing")
        XCTAssertEqual(back.payload?.sections?.first?.h, "Head")
        XCTAssertNil(back.payload?.site)
    }

    func testDmsPayloadStillDecodes() throws {
        let json = #"{"id":"dm1","kind":"dms","title":"DM","body":"md","payload":{"messages":[{"name":"Ana","note":"warm intro","msg":"Hey!"}]}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.messages?.first?.name, "Ana")
        XCTAssertNil(back.payload?.site)
    }

    func testChecklistPayloadStillDecodesFromCFShape() throws {
        let json = #"{"id":"ch1","kind":"checklist","title":"CL","body":"md","payload":{"items":[{"t":"Do it","done":true}]}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.items?.first?.t, "Do it")
        XCTAssertEqual(back.payload?.items?.first?.done, true)
        XCTAssertNil(back.payload?.site)
    }

    // MARK: - empty payload, legacy no-payload

    func testEmptyPayloadObjectDecodesToAllNilFields() throws {
        let json = #"{"id":"e1","kind":"post","title":"E","body":"md","payload":{}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertNotNil(back.payload)
        XCTAssertNil(back.payload?.items)
        XCTAssertNil(back.payload?.site)
        XCTAssertNil(back.payload?.calendar)
        XCTAssertNil(back.payload?.sheet)
        XCTAssertNil(back.payload?.screens)
    }
}
