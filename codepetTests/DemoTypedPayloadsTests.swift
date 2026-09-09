import XCTest
@testable import codepet

/// The Murror demo's filed artifacts must carry STRUCTURED payloads, not just markdown.
///
/// **Why this suite exists.** `DemoDeliverable.payloadJSON` is decoded with `try?` in
/// `DemoProject.library()`, so a payload with one wrong key, a trailing comma, or a nested
/// wrapper decodes to `nil` and the artifact renders exactly as it would with no payload at
/// all — plain markdown, no sliders, no tick boxes, no message cards. There is no error and
/// nothing goes red. Before this branch all nine filed artifacts were in that state, and it
/// took opening the app to notice: the founder ran the demo to check the export work and
/// found a sheet with no sliders, because the only typed payloads sat on runnable tasks.
///
/// So these tests assert the two things a silent `nil` would break: that the payload decoded,
/// and that export produces the kind's real file rather than falling back to `.md`.
final class DemoTypedPayloadsTests: XCTestCase {

    private func library() -> [Deliverable] { DemoProject.murror.library() }

    private func filed(_ titleFragment: String) throws -> Deliverable {
        let all = library()
        return try XCTUnwrap(
            all.first { $0.title.lowercased().contains(titleFragment.lowercased()) },
            "no filed artifact whose title contains '\(titleFragment)' — filed titles: "
                + all.map(\.title).joined(separator: " | "))
    }

    // MARK: - the payloads decoded at all

    /// The blanket guard. Every filed artifact whose kind has a structured form must have
    /// decoded one; `legal` and `text` read their body and are exempt by design.
    func testEveryFiledArtifactOfATypedKindDecodedItsPayload() throws {
        let typed: Set<DeliverableKind> = [.doc, .checklist, .plan, .sheet, .calendar, .dms, .site, .screens]
        var untyped: [String] = []
        for d in library() where typed.contains(d.kind) {
            if d.payload == nil { untyped.append("\(d.kind.rawValue): \(d.title)") }
        }
        XCTAssertTrue(untyped.isEmpty,
                      "these filed artifacts decoded no payload and will render as plain markdown:\n"
                        + untyped.joined(separator: "\n"))
    }

    func testTheFinanceSheetCarriesItsFourInputs() throws {
        let sheet = try filed("inference")
        XCTAssertEqual(sheet.kind, .sheet)
        let p = try XCTUnwrap(sheet.payload?.sheet, "the sheet payload decoded to nil")
        XCTAssertEqual(p.price.val, 6)
        XCTAssertEqual(p.waitlist.val, 400)
        XCTAssertEqual(p.conversion.val, 8)
        XCTAssertEqual(p.churn.val, 9)
        XCTAssertFalse((p.summary ?? "").isEmpty, "the summary is what the founder reads first")
    }

    func testTheOpsChecklistCarriesItsSteps() throws {
        let list = try filed("release rhythm")
        XCTAssertEqual(list.kind, .checklist)
        let items = try XCTUnwrap(list.payload?.items, "the checklist payload decoded to nil")
        XCTAssertEqual(items.count, 5)
        XCTAssertTrue(items.allSatisfy { !$0.done },
                      "a weekly rhythm starts unticked — ticking one is how the live-state export is demonstrated")
        XCTAssertTrue(items[0].t.contains("Thursday"), items[0].t)
    }

    func testEveryFiledDocLeadsWithACall() throws {
        let docs = library().filter { $0.kind == .doc }
        XCTAssertGreaterThanOrEqual(docs.count, 6, "the filed set should carry the six decision docs")
        for d in docs {
            let call = try XCTUnwrap(d.payload?.call, "no `call` on '\(d.title)' — DocViewer leads with it")
            XCTAssertFalse(call.isEmpty, d.title)
            let sections = try XCTUnwrap(d.payload?.sections, "no sections on '\(d.title)'")
            XCTAssertFalse(sections.isEmpty, d.title)
        }
    }

    // MARK: - the numbers agree with the prose

    /// The summary states 32 paying users and $192 a month. If someone edits an input without
    /// editing the sentence, the artifact contradicts itself on screen — and a founder reading
    /// a model that disagrees with its own summary has no way to tell which half is wrong.
    func testTheSheetSummaryAgreesWithTheModelItDescribes() throws {
        let sheet = try filed("inference")
        let p = try XCTUnwrap(sheet.payload?.sheet)
        let m = SheetModel.compute(price: p.price.val, waitlist: p.waitlist.val,
                                   conversion: p.conversion.val, churn: p.churn.val)
        XCTAssertEqual(m.paid, 32)
        XCTAssertEqual(m.mrr, 192)
        let summary = try XCTUnwrap(p.summary)
        XCTAssertTrue(summary.contains("32 paying users"), summary)
        XCTAssertTrue(summary.contains("$192"), summary)
    }

    // MARK: - the point of the branch: export produces the real file

    /// Before this branch every artifact in the demo Library exported as `.md`, because none
    /// carried a payload — so none of the typed export paths shipped in the export feature had
    /// anything in the demo capable of producing them.
    func testTheDemoLibraryCanProduceTheTypedExportFormats() throws {
        var produced: Set<String> = []
        for d in library() {
            for f in DeliverableExport.files(for: d) {
                produced.insert((f.name as NSString).pathExtension)
            }
        }
        XCTAssertTrue(produced.contains("csv"),
                      "no filed artifact produces a .csv — the sheet export is undemonstrable. Got: \(produced.sorted())")
        XCTAssertTrue(produced.contains("md"), "got: \(produced.sorted())")
    }

    func testTheFinanceSheetExportsACsvRatherThanMarkdown() throws {
        let files = DeliverableExport.files(for: try filed("inference"))
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].name.hasSuffix(".csv"),
                      "a payload-less sheet falls back to .md — got \(files[0].name)")
        let csv = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertTrue(csv.contains("input,value,min,max,step"), csv)
        for output in ["paid", "mrr", "arr", "ltv", "life", "breakeven"] {
            XCTAssertTrue(csv.contains("\n\(output),"), "missing the \(output) row:\n\(csv)")
        }
    }

    func testTheOpsChecklistExportsItsTickState() throws {
        let files = DeliverableExport.files(for: try filed("release rhythm"))
        let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertEqual(text.components(separatedBy: "- [ ]").count - 1, 5, text)
        XCTAssertTrue(text.contains("Thursday morning"), text)
    }

    // MARK: - the calendar export, which had no source in either demo until now

    /// `calendar` was the one export path with nothing in either demo project able to produce
    /// it: no fixture carried that kind, so `.csv` + `.ics` were reachable only from unit tests
    /// built on synthetic payloads. The launch checklist supplies one now — its body was always
    /// a T-minus schedule, and `plan` (the code-change shape) never described it.
    func testTheLaunchScheduleIsACalendarAndExportsBothFiles() throws {
        let entry = DemoProject.murror.deliverable(for: "Write the launch checklist")
        XCTAssertEqual(entry.kind, "calendar")
        let json = try XCTUnwrap(entry.payloadJSON, "the launch calendar carries no payload")
        let payload = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let weeks = try XCTUnwrap(payload.calendar?.weeks, "the calendar payload decoded to nil")
        XCTAssertEqual(weeks.count, 5, "T-7, T-5, T-2, T-0, T+7")
        XCTAssertEqual(weeks.flatMap(\.items).count, 11)
        XCTAssertTrue(weeks[0].items[0].body.contains("clinician"),
                      "the blocking item leads, because it is the one that stops a launch")

        let d = Deliverable(kind: .calendar, title: "Write the launch checklist",
                            body: "", payload: payload)
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.map(\.name), ["write-the-launch-checklist.csv",
                                           "write-the-launch-checklist.ics"])
    }

    /// The demo can now produce every export format the feature ships except the two that need
    /// `ImageRenderer` (`.pdf`, and `screens` as `.png`), which are a separate plan.
    func testTheDemoCoversEveryShippedExportFormat() throws {
        var produced: Set<String> = []
        for entry in DemoProject.murror.deliverables {
            let payload = entry.payloadJSON.flatMap {
                try? JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
            }
            let d = Deliverable(kind: DeliverableKind(raw: entry.kind), title: "Fixture probe",
                                body: entry.body, payload: payload)
            for f in DeliverableExport.files(for: d) {
                produced.insert((f.name as NSString).pathExtension)
            }
        }
        for ext in ["md", "txt", "csv", "ics", "html"] {
            XCTAssertTrue(produced.contains(ext),
                          "no fixture produces .\(ext) — that export path is undemonstrable. Got: \(produced.sorted())")
        }
    }
}
