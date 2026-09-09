// codepetTests/DeliverableExportReviewFixTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// The seven findings from the whole-branch review of the export work, each as the test that
/// was missing when the bug shipped.
///
/// Four exist because the original tests checked only the happy path:
/// `testSheetCsvOutputsMatchSheetModelForEveryField` asserts the value column and never the
/// formula strings beside it, and `testIcsEscapesBackslashSemicolonCommaAndNewlineInSummary`
/// uses `\n` and never `\r`. A guard with no test that goes red when the guard is deleted is
/// not protecting anything.
///
/// **Calendar fixtures are DECODED**, not constructed: `CalendarItem` and `CalendarWeek` each
/// declare `init(from:)`, which suppresses the memberwise initialiser. The wire shape is FLAT
/// — `weeks` sits at the top level of `payload`, with no `{"calendar": …}` wrapper. Both
/// facts are documented on `DeliverableExportTests.payload(json:)`; a fixture that ignores
/// them does not compile or does not describe production.
@MainActor
final class DeliverableExportReviewFixTests: XCTestCase {

    // MARK: - fixtures

    private func payload(json: String) throws -> DeliverablePayload {
        try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
    }

    private func deliverable(
        _ kind: DeliverableKind,
        title: String = "Untitled",
        body: String = "body text",
        payload: DeliverablePayload? = nil
    ) -> Deliverable {
        Deliverable(kind: kind, title: title, body: body, payload: payload)
    }

    /// One week, Mon and Wed, so the weekday assertion has two distinct days to find.
    private func calendarPayload() throws -> DeliverablePayload {
        try payload(json: """
        {"weeks": [
          {"label": "Week 1", "items": [
            {"day": "Mon", "kind": "post", "body": "launch note"},
            {"day": "Wed", "kind": "email", "body": "waitlist update"}
          ]}
        ]}
        """)
    }

    /// price 6, churn 6% — `SheetModel` floors churn at 1% and divides by 100, so
    /// `ltv = round(6 / 0.06) = 100` and `life = round(1 / 0.06) = 17`.
    private func sheetPayload() -> DeliverablePayload {
        DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 6, min: 0, max: 20, step: 1),
            waitlist: SheetInput(val: 1200, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 8, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: nil))
    }

    private func text(_ files: [ExportFile], ext: String) throws -> String {
        let f = try XCTUnwrap(files.first { $0.name.hasSuffix(ext) },
                              "no \(ext) file in \(files.map(\.name))")
        return try XCTUnwrap(String(data: f.data, encoding: .utf8))
    }

    private func dtstarts(_ ics: String) -> [String] {
        ics.components(separatedBy: "\r\n")
            .filter { $0.hasPrefix("DTSTART;VALUE=DATE:") }
            .map { String($0.dropFirst("DTSTART;VALUE=DATE:".count)) }
    }

    // MARK: - 1. the .ics must not depend on the founder's region

    /// A Mac set to a non-Gregorian calendar renders `yyyy` in that calendar: Buddhist gives
    /// 2569 for 2026, so `DTSTART;VALUE=DATE:25690914` — rejected outright, or dated 543
    /// years out. `icsTimestamp` sets `en_US_POSIX`; `icsDate` did not.
    func testIcsDatesAreIdenticalWhateverCalendarTheMacIsSetTo() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let posix = try text(DeliverableExport.files(for: d, locale: Locale(identifier: "en_US_POSIX")),
                             ext: ".ics")
        let buddhist = try text(DeliverableExport.files(for: d, locale: Locale(identifier: "th_TH@calendar=buddhist")),
                                ext: ".ics")

        XCTAssertFalse(dtstarts(posix).isEmpty, "no DTSTART lines at all")
        XCTAssertEqual(dtstarts(posix), dtstarts(buddhist),
                       "the exported .ics changed because of the founder's region setting")
    }

    /// Stated separately so a regression making both locales equally wrong still fails.
    func testIcsDateIsEightGregorianDigits() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try text(DeliverableExport.files(for: d, locale: Locale(identifier: "th_TH@calendar=buddhist")),
                           ext: ".ics")
        let stamps = dtstarts(ics)
        XCTAssertFalse(stamps.isEmpty, "no DTSTART lines at all")
        for s in stamps {
            XCTAssertEqual(s.count, 8, "DTSTART \(s) is not yyyyMMdd")
            XCTAssertTrue(s.allSatisfy { $0.isASCII && $0.isNumber },
                          "DTSTART \(s) is not ASCII digits")
            XCTAssertTrue((2020...2100).contains(Int(s.prefix(4)) ?? 0),
                          "DTSTART \(s) has a non-Gregorian year")
        }
    }

    // MARK: - 2. the formula column must describe the arithmetic that produced the value

    /// `churn` is a percent in the input block (`churn,6,0,30,1`) and `SheetModel` divides it
    /// by 100. `round(price / churn)` with those numbers is 1, not the 100 printed beside it.
    /// The formula column exists so the reader can disagree with the derivation; a wrong
    /// derivation defeats it.
    func testSheetCsvLtvAndLifeFormulasDivideChurnByOneHundred() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try text(DeliverableExport.files(for: d), ext: ".csv")
        let rows = csv.components(separatedBy: "\n")

        let ltv = try XCTUnwrap(rows.first { $0.hasPrefix("ltv,") })
        let life = try XCTUnwrap(rows.first { $0.hasPrefix("life,") })

        XCTAssertTrue(ltv.contains("churn / 100"),
                      "ltv formula does not divide churn by 100: \(ltv)")
        XCTAssertTrue(life.contains("churn / 100"),
                      "life formula does not divide churn by 100: \(life)")
    }

    /// The values are already right; pinned so the formula fix cannot be "corrected" by
    /// changing the arithmetic instead of the prose.
    func testSheetCsvLtvAndLifeValuesStillMatchTheModel() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try text(DeliverableExport.files(for: d), ext: ".csv")
        XCTAssertTrue(csv.contains("\nltv,100,"), "ltv value changed:\n\(csv)")
        XCTAssertTrue(csv.contains("\nlife,17,"), "life value changed:\n\(csv)")
    }

    // MARK: - 3. a wire number must not crash the export

    /// `n(_:)` used `String(Int(v))`, and `Int(_ Double)` traps. These values arrive straight
    /// from the model-generated payload with no magnitude guard, so one absurd bound hard-
    /// crashed the app the moment the founder pressed Export.
    func testAnAbsurdSliderBoundDoesNotCrashTheExport() throws {
        let p = DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 6, min: 0, max: 1e19, step: 1),
            waitlist: SheetInput(val: 1200, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 8, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: nil))
        let d = deliverable(.sheet, title: "Pricing model", payload: p)

        let csv = try text(DeliverableExport.files(for: d), ext: ".csv")
        let price = try XCTUnwrap(csv.components(separatedBy: "\n").first { $0.hasPrefix("price,") })
        XCTAssertFalse(price.lowercased().contains("e+"),
                       "an absurd bound rendered in scientific notation: \(price)")
        XCTAssertFalse(price.lowercased().contains("inf"),
                       "an absurd bound rendered as inf: \(price)")
    }

    /// Non-finite input reaches the same formatter. `SheetModel.compute` guards it; the
    /// formatter guarded neither non-finite nor out-of-range.
    func testNonFiniteSliderBoundDoesNotCrashTheExport() throws {
        let p = DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 6, min: -.infinity, max: .infinity, step: .nan),
            waitlist: SheetInput(val: 1200, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 8, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: nil))
        let d = deliverable(.sheet, title: "Pricing model", payload: p)

        let csv = try text(DeliverableExport.files(for: d), ext: ".csv")
        XCTAssertTrue(csv.hasPrefix("input,value,min,max,step\n"), csv)
    }

    // MARK: - 4. the .ics must not silently drop the weekday

    /// `icsDate` maps week-1 "Mon" to TODAY whatever weekday today is, and `DESCRIPTION` says
    /// the day is relative — but the weekday Marketing actually chose appeared nowhere in the
    /// file, while the CSV kept it. Export on a Friday and a Mon/Wed week lands Fri/Sun with
    /// nothing recording the intent.
    func testEveryEventNamesTheWeekdayItWasPlannedFor() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try text(DeliverableExport.files(for: d), ext: ".ics")
        let events = Array(ics.components(separatedBy: "BEGIN:VEVENT").dropFirst())

        XCTAssertEqual(events.count, 2, "expected two events in:\n\(ics)")
        for (event, day) in zip(events, ["Mon", "Wed"]) {
            XCTAssertTrue(event.contains(day),
                          "the event does not record the planned weekday \(day):\n\(event)")
        }
    }

    // MARK: - 5. a carriage return must not reach the property value

    /// RFC 5545 line breaks are CRLF, so a bare `\r` inside `SUMMARY:` is a line break to a
    /// strict parser — the same split-across-two-lines corruption the escaping exists to
    /// stop. The existing escaping test uses only `\n`, so this went unnoticed.
    func testIcsEscapesCarriageReturnsNotJustNewlines() throws {
        let p = try payload(json: """
        {"weeks": [
          {"label": "Week 1", "items": [
            {"day": "Mon", "kind": "post", "body": "first line\\r\\nsecond line\\rthird"}
          ]}
        ]}
        """)
        let d = deliverable(.calendar, title: "Content calendar", payload: p)
        let ics = try text(DeliverableExport.files(for: d), ext: ".ics")

        let summary = try XCTUnwrap(ics.components(separatedBy: "\r\n")
            .first { $0.hasPrefix("SUMMARY:") }, "no SUMMARY line in:\n\(ics)")

        XCTAssertFalse(summary.contains("\r"), "a bare CR survived into SUMMARY: \(summary)")
        // Three logical lines, so two escaped breaks — a dropped CR would leave one.
        XCTAssertEqual(summary.components(separatedBy: "\\n").count - 1, 2,
                       "expected two escaped breaks in: \(summary)")
    }

    // MARK: - 6. the set-level header must line up with the cards beneath it

    /// `DmsViewer`'s message cards get their 16pt inset from `deliverableCardChrome`; the new
    /// set-level header got no chrome and no padding, so its eyebrow and its rule drew flush
    /// to the sheet edge — 16pt out of alignment with every card below, the rule full-bleeding
    /// past both card borders.
    ///
    /// `ImageRenderer` at `scale = 1` on a canvas WIDER than the view, the technique
    /// `EngineeringResultBarLayoutTests` documents: rendering at the view's own width clips
    /// overflow away and makes the assertion vacuous.
    func testDmsSetHeaderIsInsetToMatchTheMessageCards() throws {
        let messages = [DmMessage(name: "Ari", note: "runs the newsletter", msg: "hello there")]
        let d = deliverable(.dms, title: "Outreach",
                            payload: DeliverablePayload(messages: messages))

        let header = DmsSetHeader(messages: messages, deliverable: d)
            .environment(\.uiLanguage, .en)

        let extent = try XCTUnwrap(drawnExtent(header, width: 520), "the header drew nothing")
        XCTAssertEqual(CGFloat(extent.first), DeliverableStyle.padding, accuracy: 2,
                       "header draws at x=\(extent.first); a card's content starts at \(DeliverableStyle.padding)")
    }

    /// Leftmost and rightmost drawn pixel column, or nil when nothing drew.
    private func drawnExtent(_ view: some View, width: CGFloat) -> (first: Int, last: Int)? {
        let canvas: CGFloat = 700
        let renderer = ImageRenderer(content: view.frame(width: width)
                                                  .frame(width: canvas, alignment: .leading))
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let rowBytes = cg.bytesPerRow, pixelBytes = cg.bitsPerPixel / 8
        var first: Int?, last: Int?
        for x in 0..<cg.width {
            var drew = false
            for y in 0..<cg.height where bytes[y * rowBytes + x * pixelBytes + (pixelBytes - 1)] > 8 {
                drew = true
                break
            }
            if drew {
                if first == nil { first = x }
                last = x
            }
        }
        guard let f = first, let l = last else { return nil }
        return (f, l)
    }

    // MARK: - 7. a partial failure must not read as a success

    /// `"Saved 2 of 4"` in muted text, with no failure wording, is what a founder saw when a
    /// four-file `dms` export died after two files. The same silent-success failure mode the
    /// enable-card carried: the control acted, said something reassuring, and the founder had
    /// no way to know it had broken.
    func testPartialExportFailureIsWordedAsAFailure() {
        let en = DeliverableExportButton.failureText(landed: 2, total: 4, lang: .en)
        XCTAssertTrue(en.lowercased().contains("failed"),
                      "a partial failure does not say it failed: \(en)")
        XCTAssertTrue(en.contains("2") && en.contains("4"),
                      "a partial failure lost the counts: \(en)")

        let vi = DeliverableExportButton.failureText(landed: 2, total: 4, lang: .vi)
        XCTAssertTrue(vi.contains("thất bại"),
                      "the Vietnamese partial failure does not say it failed: \(vi)")
    }

    /// The total failure was already worded correctly; pinned so the partial fix does not
    /// regress it into saying "0 of 4".
    func testTotalExportFailureStillReadsAsAPlainFailure() {
        XCTAssertEqual(DeliverableExportButton.failureText(landed: 0, total: 4, lang: .en),
                       "Export failed")
        XCTAssertEqual(DeliverableExportButton.failureText(landed: 0, total: 4, lang: .vi),
                       "Xuất thất bại")
    }
}
