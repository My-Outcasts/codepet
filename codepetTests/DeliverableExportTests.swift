import XCTest
@testable import codepet

/// `DeliverableExport` is a pure function from a deliverable to file bytes, which is the
/// whole reason it is a type and not view code: a `WKWebView` or an `NSSavePanel` cannot be
/// asserted on, and these can.
final class DeliverableExportTests: XCTestCase {

    private func deliverable(
        _ kind: DeliverableKind,
        title: String = "Untitled",
        body: String = "body text",
        payload: DeliverablePayload? = nil
    ) -> Deliverable {
        Deliverable(kind: kind, title: title, body: body, payload: payload)
    }

    /// Some payload fixtures are DECODED from JSON rather than constructed.
    ///
    /// `SitePayload`, `CalendarItem` and `CalendarWeek` each declare their own
    /// `init(from decoder:)`, which **suppresses Swift's memberwise initialiser** — so
    /// `SitePayload(title:brand:…)` does not exist and will not compile. Decoding is also
    /// how these arrive in production, which makes it the more honest fixture.
    ///
    /// `ChecklistItem`, `DocSection`, `PlanChange`, `DmMessage`, `SheetInput`,
    /// `SheetPayload`, `SiteContent` and `CalendarPayload` declare no initialiser and DO
    /// have a memberwise init, so those are constructed directly below.
    ///
    /// **The payload wire shape is FLAT.** `DeliverablePayload.init(from:)` decodes the
    /// nested structs off the SAME decoder — `try? CalendarPayload(from: decoder)` — because
    /// the generator's `record_deliverable` schema puts `weeks`, `price`, `title`, `brand`,
    /// `steps` and `screens` at the top level of `payload`. There is no `{"calendar": {...}}`
    /// wrapper on the wire, and a fixture that invents one does not describe production.
    /// This is also what the `steps` key collision between `plan` ([String]) and `site`
    /// ([SiteContent]) is about, and why each nested decode is `try?`.
    private func payload(json: String) throws -> DeliverablePayload {
        try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
    }

    // MARK: - slug

    func testSlugStripsPathAndPunctuationThatBreaksAFilename() {
        XCTAssertEqual(DeliverableExport.slug("Q4 Pricing / Model: v2"), "q4-pricing-model-v2")
    }

    func testSlugFoldsVietnameseDiacriticsRatherThanDroppingTheName() {
        XCTAssertEqual(DeliverableExport.slug("Kế hoạch ra mắt"), "ke-hoach-ra-mat")
    }

    func testSlugFallsBackWhenNothingSurvives() {
        XCTAssertEqual(DeliverableExport.slug("///", fallback: "deliverable"), "deliverable")
    }

    // MARK: - markdown kinds

    func testDocExportsOneMarkdownFileNamedFromTheTitle() throws {
        let d = deliverable(.doc, title: "What the app is built on")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "what-the-app-is-built-on.md")
    }

    func testDocMarkdownLeadsWithTheCallBecauseTheViewerDoes() throws {
        let d = deliverable(.doc, title: "Stack", body: "ignored for doc",
                            payload: DeliverablePayload(
                                call: "Run on-device where the entry can stay.",
                                sections: [DocSection(h: "Why", p: "Privacy is the product.")],
                                next: ["Measure recall past 3k entries"]))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("# Stack\n\nRun on-device where the entry can stay."), text)
        XCTAssertTrue(text.contains("## Why"), text)
        XCTAssertTrue(text.contains("Privacy is the product."), text)
        XCTAssertTrue(text.contains("- Measure recall past 3k entries"), text)
    }

    func testChecklistExportsTickBoxesSoTheStateSurvivesTheFile() throws {
        let d = deliverable(.checklist, title: "Release rhythm",
                            payload: DeliverablePayload(items: [
                                ChecklistItem(t: "Tag the build", done: true),
                                ChecklistItem(t: "Notarise", done: false),
                            ]))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(text.contains("- [x] Tag the build"), text)
        XCTAssertTrue(text.contains("- [ ] Notarise"), text)
    }

    func testPlanExportsGoalStepsChangesVerifyAndRisk() throws {
        let d = deliverable(.plan, title: "Add export",
                            payload: DeliverablePayload(
                                goal: "Let a founder save a deliverable",
                                steps: ["Add the pure core", "Add the panel"],
                                changes: [PlanChange(area: "Library viewers", edit: "one export slot")],
                                verify: ["A saved .md opens in any editor"],
                                risks: "A title with a slash breaks the filename"))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        for expected in ["Let a founder save a deliverable", "1. Add the pure core",
                         "Library viewers", "one export slot",
                         "A saved .md opens in any editor",
                         "A title with a slash breaks the filename"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in:\n\(text)")
        }
    }

    /// A kind with no payload still exports — the body is the deliverable. `.legal` is the
    /// case that matters: its viewer reads only `body`, and the schema's `sections` is dead
    /// for it (see the spec's Layer 2 note).
    func testLegalAndTextFallBackToTheMarkdownBody() throws {
        for kind in [DeliverableKind.legal, .text, .other] {
            let d = deliverable(kind, title: "Deletion promise", body: "One tap. Permanent.")
            let files = DeliverableExport.files(for: d)
            XCTAssertEqual(files.count, 1, "\(kind)")
            XCTAssertEqual(files[0].name, "deletion-promise.md", "\(kind)")
            let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
            XCTAssertTrue(text.contains("One tap. Permanent."), "\(kind): \(text)")
        }
    }

    func testEveryKindProducesAtLeastOneFile() {
        for kind in DeliverableKind.allCases {
            let d = deliverable(kind, title: "Anything", body: "some body")
            XCTAssertFalse(DeliverableExport.files(for: d).isEmpty,
                           "\(kind) exported nothing — a founder would see a dead button")
        }
    }

    // MARK: - sendable text

    func testPostExportsPlainTextNotMarkdown() throws {
        let d = deliverable(.post, title: "Launch post", body: "We built a journal that answers.")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "launch-post.txt")
        let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertEqual(text, "We built a journal that answers.\n")
    }

    /// No `# Title` heading: a post is pasted into a composer, and a markdown heading pasted
    /// into X is a literal hash.
    func testPostCarriesNoMarkdownHeading() throws {
        let d = deliverable(.post, title: "Launch post", body: "Body only.")
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertFalse(text.contains("#"), text)
    }

    func testDmsExportsOneFilePerMessageBecauseEachGoesToSomeoneElse() throws {
        let d = deliverable(.dms, title: "Early access",
                            payload: DeliverablePayload(messages: [
                                DmMessage(name: "Lapsed journaler", note: "quit over streaks",
                                          msg: "We cut the streak counter. Want the first build?"),
                                DmMessage(name: "Privacy-first buyer", note: "asked about training",
                                          msg: "Nothing leaves your phone unless you ask."),
                            ]))
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].name, "early-access-1-lapsed-journaler.txt")
        XCTAssertEqual(files[1].name, "early-access-2-privacy-first-buyer.txt")
        let first = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertTrue(first.contains("We cut the streak counter."), first)
        XCTAssertTrue(first.contains("quit over streaks"), "the note says why this target — keep it")
    }

    func testDmsWithNoMessagesStillExportsTheBody() throws {
        let d = deliverable(.dms, title: "Outreach", body: "the prose version")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "outreach.txt")
    }

    func testEmailExportsAsText() throws {
        let d = deliverable(.email, title: "Day 14 check-in", body: "How has the first fortnight been?")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files[0].name, "day-14-check-in.txt")
    }

    // MARK: - sheet

    private func sheetPayload() -> DeliverablePayload {
        DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 6, min: 0, max: 20, step: 1),
            waitlist: SheetInput(val: 1200, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 8, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: "At $6 and 8% conversion the model clears cost."))
    }

    func testSheetExportsCsvNotMarkdown() {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "pricing-model.csv")
    }

    func testSheetCsvCarriesEveryInputWithItsRange() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.hasPrefix("input,value,min,max,step\n"), csv)
        XCTAssertTrue(csv.contains("price,6,0,20,1"), csv)
        XCTAssertTrue(csv.contains("waitlist,1200,0,5000,50"), csv)
        XCTAssertTrue(csv.contains("conversion,8,0,50,1"), csv)
        XCTAssertTrue(csv.contains("churn,6,0,30,1"), csv)
    }

    /// The point of exporting a model rather than a number: the reader can see how it was
    /// derived and disagree with it.
    ///
    /// **This is the sheet CSV's equivalent of `testExportedHtmlIsByteIdenticalToWhatTheViewerRenders`**
    /// — it exists to stop the CSV growing a second renderer that can silently disagree with
    /// `SheetViewer`. All six of `SheetModel.compute`'s fields must appear, computed by
    /// calling the model itself, not by re-deriving them here.
    func testSheetCsvOutputsMatchSheetModelForEveryField() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        let m = SheetModel.compute(price: 6, waitlist: 1200, conversion: 8, churn: 6)
        XCTAssertTrue(csv.contains("output,value,formula"), csv)
        XCTAssertTrue(csv.contains("paid,\(m.paid),"), "got:\n\(csv)")
        XCTAssertTrue(csv.contains("mrr,\(Int(m.mrr)),"), "got:\n\(csv)")
        XCTAssertTrue(csv.contains("arr,\(Int(m.arr)),"), "got:\n\(csv)")
        XCTAssertTrue(csv.contains("ltv,\(m.ltv),"), "got:\n\(csv)")
        XCTAssertTrue(csv.contains("life,\(m.life),"), "got:\n\(csv)")
        XCTAssertTrue(csv.contains("breakeven,\(m.breakeven),"), "got:\n\(csv)")
    }

    /// `SheetModel` floors `price` at 1, so a `price` of 0 does not zero out MRR on screen —
    /// the viewer shows the floored model's MRR. Before this fix the CSV hand-computed
    /// `subscribers * price` with the RAW (unfloored) price and wrote `mrr,0`: a founder
    /// comparing the file to the screen would see the two disagree on the number that matters
    /// most in this export.
    func testSheetCsvMrrUsesTheFlooredPriceNotZero() throws {
        let payload = DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 0, min: 0, max: 20, step: 1),
            waitlist: SheetInput(val: 1200, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 8, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: nil))
        let d = deliverable(.sheet, title: "Pricing model", payload: payload)
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        let m = SheetModel.compute(price: 0, waitlist: 1200, conversion: 8, churn: 6)
        XCTAssertGreaterThan(m.mrr, 0, "the model itself must floor price — otherwise this test proves nothing")
        XCTAssertFalse(csv.contains("mrr,0,"), "the CSV must not disagree with the floored model — got:\n\(csv)")
        XCTAssertTrue(csv.contains("mrr,\(Int(m.mrr)),"), "got:\n\(csv)")
    }

    /// Closes a carried finding: the decimal branch of the CSV's number formatter was
    /// entirely untested, and `%.4g` silently destroyed large fractional currency
    /// (`n(9999.99)` → `"1e+04"`). Fractional inputs must render in full, fixed-decimal form.
    func testSheetCsvRendersFractionalCurrencyInFullNotScientificNotation() throws {
        let payload = DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 19.99, min: 0, max: 100, step: 0.01),
            waitlist: SheetInput(val: 5000, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 50, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: nil))
        let d = deliverable(.sheet, title: "Pricing model", payload: payload)
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.contains("price,19.99,"), "got:\n\(csv)")
        XCTAssertFalse(csv.lowercased().contains("e+"), "scientific notation leaked into the CSV — got:\n\(csv)")
        let m = SheetModel.compute(price: 19.99, waitlist: 5000, conversion: 50, churn: 6)
        XCTAssertGreaterThan(m.mrr, 9999, "the fixture must actually exercise a large fractional MRR")
        let expectedMrr = String(format: "%.2f", m.mrr)
        XCTAssertTrue(csv.contains("mrr,\(expectedMrr),"), "large MRR must render in full — got:\n\(csv)")
    }

    func testSheetCsvQuotesTheSummarySoACommaCannotSplitIt() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.contains("\"At $6 and 8% conversion the model clears cost.\""), csv)
    }

    func testSheetWithNoPayloadFallsBackToMarkdown() {
        let d = deliverable(.sheet, title: "Pricing model", body: "prose only")
        XCTAssertEqual(DeliverableExport.files(for: d)[0].name, "pricing-model.md")
    }

    // MARK: - calendar

    /// Decoded, not constructed — `CalendarWeek` and `CalendarItem` both declare
    /// `init(from:)` and therefore have no memberwise initialiser. See `payload(json:)`.
    ///
    /// **Flat, not nested.** `DeliverablePayload` decodes `CalendarPayload` off the same
    /// decoder, because the generator puts `weeks` at the top level of `payload`.
    private func calendarPayload() throws -> DeliverablePayload {
        try payload(json: """
        {"weeks": [
          {"label": "Week 1", "items": [
            {"day": "Mon", "kind": "thread", "body": "Why I'm building a journal that answers"},
            {"day": "Fri", "kind": "post", "body": "What we refuse to do on a bad night"}
          ]},
          {"label": "Week 2", "items": [
            {"day": "Tue", "kind": "post", "body": "On-device vs server"}
          ]}
        ]}
        """)
    }

    func testCalendarExportsBothASpreadsheetAndACalendarFile() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let names = DeliverableExport.files(for: d).map(\.name)
        XCTAssertEqual(names, ["content-calendar.csv", "content-calendar.ics"])
    }

    /// Every field is quoted, including week/day/kind. They are model-authored strings and
    /// can contain a comma; a reader never sees the difference and a stray comma cannot shift
    /// a column.
    func testCalendarCsvHasOneRowPerItemWithItsWeek() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.hasPrefix("week,day,kind,body\n"), csv)
        XCTAssertEqual(csv.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 4,
                       "header + 3 items — got:\n\(csv)")
        XCTAssertTrue(csv.contains("\"Week 1\",\"Mon\",\"thread\",\"Why I'm building a journal that answers\""), csv)
    }

    /// An .ics with no VEVENT is a file that opens to nothing.
    func testIcsWrapsEveryItemAsAnEvent() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"), ics)
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"), ics)
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 3, ics)
        XCTAssertTrue(ics.contains("SUMMARY:Why I'm building a journal that answers"), ics)
    }

    /// The founder's calendar app must not reject the file. Every VEVENT needs a UID —
    /// and, on the same axis, a DTSTAMP: RFC 5545 requires it on every VEVENT, and while
    /// Apple and Google tolerate its absence, Outlook and strict validators do not.
    func testEveryEventCarriesAUidAndADtstamp() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        XCTAssertEqual(ics.components(separatedBy: "UID:").count - 1, 3, ics)
        let dtstampLines = ics.components(separatedBy: "\r\n").filter { $0.hasPrefix("DTSTAMP:") }
        XCTAssertEqual(dtstampLines.count, 3, ics)
        // DTSTAMP must be a valid RFC 5545 basic UTC datetime (yyyyMMdd'T'HHmmss'Z'), not
        // merely present: 8 digits, "T", 6 digits, "Z".
        for line in dtstampLines {
            let stamp = line.dropFirst("DTSTAMP:".count)
            XCTAssertEqual(stamp.count, 16, "expected yyyyMMdd'T'HHmmss'Z' — got \(stamp)")
            let digitsOnly = stamp.filter(\.isNumber)
            XCTAssertEqual(digitsOnly.count, 14, "expected 14 digits — got \(stamp)")
            XCTAssertTrue(stamp.hasSuffix("Z"), "expected a trailing Z — got \(stamp)")
            XCTAssertEqual(stamp[stamp.index(stamp.startIndex, offsetBy: 8)], "T", "expected T at offset 8 — got \(stamp)")
        }
    }

    // MARK: - RFC 5545 escaping

    /// Independently mirrors `DeliverableExport.icsEscaped`'s spec (RFC 5545 §3.3.11: a
    /// backslash, a semicolon, a comma and a newline), computed here rather than by calling
    /// the private production function — the "expected" string in the test below must not
    /// depend on the very code under test.
    private func rfc5545Escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// `icsEscaped` was completely unfalsified before this test: the only SUMMARY assertion
    /// elsewhere in this file (`testIcsWrapsEveryItemAsAnEvent`) uses a string whose sole
    /// punctuation is an apostrophe, which RFC 5545 does not escape — you could delete
    /// `icsEscaped`'s body and every existing test would stay green. This fixture drives all
    /// four characters the function claims to escape: backslash, semicolon, comma, newline.
    ///
    /// Built via `JSONSerialization` rather than a hand-typed JSON string literal — escaping
    /// a literal backslash and a literal newline correctly inside hand-typed JSON source is
    /// exactly the kind of thing that is easy to get subtly wrong, and `JSONSerialization`
    /// does it correctly by construction.
    func testIcsEscapesBackslashSemicolonCommaAndNewlineInSummary() throws {
        let rawBody = "Ship, then tell people; carefully\\next week\nlater"
        // Confirm the fixture itself carries all four characters, unescaped — otherwise this
        // test could pass for the wrong reason.
        XCTAssertTrue(rawBody.contains(","), rawBody)
        XCTAssertTrue(rawBody.contains(";"), rawBody)
        XCTAssertTrue(rawBody.contains("\\"), rawBody)
        XCTAssertTrue(rawBody.contains("\n"), rawBody)

        let dict: [String: Any] = ["weeks": [["label": "Week 1",
                                               "items": [["day": "Mon", "kind": "thread", "body": rawBody]]]]]
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        let p = try payload(json: json)

        let d = deliverable(.calendar, title: "Content calendar", payload: p)
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        let expected = rfc5545Escaped(rawBody)
        XCTAssertTrue(ics.contains("SUMMARY:\(expected)\r\n"), "got:\n\(ics)")
    }

    /// The rule the .ics exists to respect: the generator emits a RELATIVE schedule, so the
    /// file must say so rather than presenting a computed day as a real commitment. Without
    /// this, a founder reads Codepet's arithmetic as Marketing's chosen date.
    func testEveryEventSaysItsDayIsRelative() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        XCTAssertEqual(ics.components(separatedBy: "DESCRIPTION:").count - 1, 3,
                       "every event needs a DESCRIPTION carrying the caveat — got:\n\(ics)")
        XCTAssertEqual(ics.components(separatedBy: "day is relative to export").count - 1, 3,
                       "each DESCRIPTION must say the day is relative — got:\n\(ics)")
    }

    func testCalendarWithNoPayloadFallsBackToMarkdown() {
        let d = deliverable(.calendar, title: "Content calendar", body: "prose only")
        XCTAssertEqual(DeliverableExport.files(for: d).map(\.name), ["content-calendar.md"])
    }

    // MARK: - site

    /// Decoded, not constructed — `SitePayload` declares `init(from:)` and so has no
    /// memberwise initialiser. `title`, `brand`, `headline`, `ctaPrimary`, `finalTitle` and
    /// `finalCta` are REQUIRED anchors that throw when absent; everything else is soft.
    private func sitePayload() throws -> DeliverablePayload {
        try payload(json: """
        {
          "title": "Murror — a journal that answers",
          "brand": "Murror",
          "headline": "A journal that answers",
          "sub": "Private by design. Nothing leaves your phone unless you ask.",
          "ctaPrimary": "Get early access",
          "howEyebrow": "How it works",
          "howTitle": "Three steps",
          "steps": [{"h": "Write", "p": "Say anything."}],
          "featEyebrow": "Why",
          "featTitle": "What makes it different",
          "features": [{"h": "No streaks", "p": "We cut them."}],
          "finalTitle": "Start tonight",
          "finalCta": "Get early access",
          "accent": "80C830",
          "footNote": "Murror"
        }
        """)
    }

    func testSiteExportsOneHtmlFile() throws {
        let d = deliverable(.site, title: "Landing page", payload: try sitePayload())
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "landing-page.html")
    }

    /// Ready to host means a complete document, not a fragment.
    func testExportedSiteIsACompleteDocument() throws {
        let d = deliverable(.site, title: "Landing page", payload: try sitePayload())
        let html = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(html.lowercased().contains("<!doctype html"), String(html.prefix(200)))
        XCTAssertTrue(html.contains("</html>"), String(html.suffix(200)))
        XCTAssertTrue(html.contains("A journal that answers"), "the headline is missing")
    }

    /// The exported file and the on-screen page come from ONE builder. If this ever fails,
    /// export has grown a second renderer and the two can disagree.
    func testExportedHtmlIsByteIdenticalToWhatTheViewerRenders() throws {
        let fixture = try sitePayload()
        let p = try XCTUnwrap(fixture.site)
        let d = deliverable(.site, title: "Landing page", payload: fixture)
        let exported = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertEqual(exported, SiteViewer.buildHTML(p))
    }

    func testSiteWithNoPayloadFallsBackToMarkdown() {
        let d = deliverable(.site, title: "Landing page", body: "copy only")
        XCTAssertEqual(DeliverableExport.files(for: d)[0].name, "landing-page.md")
    }

    // MARK: - I4: Export takes what is on screen, matching Copy

    /// `ChecklistViewer` reads live `@State`, unreachable from a test — so the payload-rebuild
    /// step is a pure static, `exportSubject(_:items:)`, tested directly here rather than
    /// through the view. Ticking a box in the view mutates its `items` array exactly the way
    /// this test constructs one; the assertion is that Export renders THAT, not the untouched
    /// payload the deliverable arrived with.
    func testChecklistExportSubjectReflectsLiveTicks() throws {
        let untouched = deliverable(.checklist, title: "Launch checklist",
                                    payload: DeliverablePayload(items: [
                                        ChecklistItem(t: "Tag the build", done: false),
                                        ChecklistItem(t: "Write the notes", done: false)]))
        // Simulates the founder ticking the first box — what `ChecklistViewer` would have
        // done to its own `@State private var items` by this point.
        let ticked = [ChecklistItem(t: "Tag the build", done: true),
                      ChecklistItem(t: "Write the notes", done: false)]
        let subject = ChecklistViewer.exportSubject(untouched, items: ticked)

        XCTAssertEqual(subject.id, untouched.id)
        XCTAssertEqual(subject.kind, untouched.kind)
        XCTAssertEqual(subject.title, untouched.title)

        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: subject)[0].data,
                                        encoding: .utf8))
        XCTAssertTrue(text.contains("- [x] Tag the build"), text)
        XCTAssertTrue(text.contains("- [ ] Write the notes"), text)

        // And the untouched deliverable's own export is unaffected — `exportSubject` copies
        // rather than mutating in place.
        let originalText = try XCTUnwrap(String(data: DeliverableExport.files(for: untouched)[0].data,
                                                 encoding: .utf8))
        XCTAssertTrue(originalText.contains("- [ ] Tag the build"), originalText)
    }

    /// `SheetViewer` reads its sliders' live `@State`, also unreachable from a test — same
    /// fix, `exportSubject(_:price:waitlist:conversion:churn:)`. Moving a slider changes only
    /// `SheetInput.val`; `min`/`max`/`step` never move, and the test pins that too.
    func testSheetExportSubjectReflectsLiveSliderValues() throws {
        let payload = DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 20, min: 5, max: 100, step: 1),
            waitlist: SheetInput(val: 500, min: 0, max: 5000, step: 10),
            conversion: SheetInput(val: 10, min: 0, max: 100, step: 1),
            churn: SheetInput(val: 4, min: 0, max: 50, step: 1),
            summary: nil))
        let untouched = deliverable(.sheet, title: "Pricing model", payload: payload)

        // Simulates the founder dragging the price and waitlist sliders.
        let subject = SheetViewer.exportSubject(untouched, price: 35, waitlist: 1200,
                                                conversion: 10, churn: 4)

        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: subject)[0].data,
                                       encoding: .utf8))
        XCTAssertTrue(csv.contains("price,35,5,100,1"), csv)
        XCTAssertTrue(csv.contains("waitlist,1200,0,5000,10"), csv)
        // Untouched inputs carry their range through unchanged.
        XCTAssertTrue(csv.contains("conversion,10,0,100,1"), csv)
        XCTAssertTrue(csv.contains("churn,4,0,50,1"), csv)

        // The original deliverable's export is unaffected.
        let originalCsv = try XCTUnwrap(String(data: DeliverableExport.files(for: untouched)[0].data,
                                               encoding: .utf8))
        XCTAssertTrue(originalCsv.contains("price,20,5,100,1"), originalCsv)
    }
}
