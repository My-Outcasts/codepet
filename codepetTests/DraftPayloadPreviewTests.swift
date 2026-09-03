// codepetTests/DraftPayloadPreviewTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// Guards on the card showing the deliverable rather than describing where it is.
///
/// `draftCard` rendered `DraftPreview.plain(d.body)` under a `lineLimit` and never read
/// `d.payload` at all, so every structured viewer was reachable only from the Library. Finance's
/// four-input pricing model arrived as a truncated paragraph, and the landing page arrived as a
/// sentence reading *"The page is live in your Library — open it to see it rendered."*
///
/// The dispatch is pulled out as `hasStructuredPreview` precisely so it is testable without
/// rendering anything: the decision is where the bug lived, not the layout.
final class DraftPayloadPreviewTests: XCTestCase {

    private func deliverable(_ kind: DeliverableKind, payloadJSON: String?) throws -> Deliverable {
        let payload = try payloadJSON.map {
            try JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
        }
        // NOTE the argument order: `Deliverable.init` takes `kind` BEFORE `title`, which reads
        // backwards from the struct's own field order.
        return Deliverable(id: "t", kind: kind, title: "T", body: "Body text.", payload: payload)
    }

    // MARK: - The dispatch

    /// **Keyed on the PAYLOAD, not the kind.** Dispatching on kind alone renders an empty
    /// structured view whenever a payload did not arrive — three blank slider rows, a checklist
    /// with no items — and a founder cannot tell that from a broken card.
    func testStructuredPreviewRequiresAPayload() throws {
        let withNone = try deliverable(.sheet, payloadJSON: nil)
        XCTAssertFalse(DraftPayloadPreview.hasStructuredPreview(withNone),
                       "a nil payload must fall back to prose, not render an empty sheet")
    }

    func testSheetWithAPayloadGetsAStructuredPreview() throws {
        let d = try deliverable(.sheet, payloadJSON: """
        {"price":{"val":6,"min":0,"max":20,"step":1},
         "waitlist":{"val":400,"min":50,"max":5000,"step":50},
         "conversion":{"val":8,"min":1,"max":40,"step":1},
         "churn":{"val":9,"min":1,"max":25,"step":1},"summary":"S"}
        """)
        XCTAssertTrue(DraftPayloadPreview.hasStructuredPreview(d))
    }

    /// The end-to-end claim of §1, asserted against the real Murror fixtures rather than a stub:
    /// every deliverable that carries a payload must reach a structured branch.
    func testEveryMurrorPayloadReachesAStructuredPreview() throws {
        var checked = 0
        for entry in DemoProject.murror.deliverables where entry.payloadJSON != nil {
            let kind = try XCTUnwrap(DeliverableKind(rawValue: entry.kind))
            let d = try deliverable(kind, payloadJSON: entry.payloadJSON)
            XCTAssertTrue(DraftPayloadPreview.hasStructuredPreview(d),
                          "\(entry.kind) carries a payload but would render prose")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no Murror payloads were checked — the fixture changed")
    }

    /// A kind with no structured branch keeps prose even when a payload happens to decode.
    func testAnUnhandledKindFallsBackToProse() throws {
        let d = try deliverable(.email, payloadJSON: #"{"items":[{"t":"a","done":false}]}"#)
        XCTAssertFalse(DraftPayloadPreview.hasStructuredPreview(d))
    }

    /// An empty collection is the same as no payload: there is nothing to show.
    func testAnEmptyCollectionFallsBackToProse() throws {
        let d = try deliverable(.checklist, payloadJSON: #"{"items":[]}"#)
        XCTAssertFalse(DraftPayloadPreview.hasStructuredPreview(d))
    }

    // MARK: - The accent

    /// `SiteViewer.safeHex` validates hex SYNTAX, not contrast — so nothing else in the codebase
    /// would catch a malformed accent painting a broken swatch.
    func testMalformedAccentFallsBackToTheHouseAccent() {
        XCTAssertEqual(DraftPayloadPreview.safeAccent("not-a-hex"), CodepetTheme.accentPurple)
        XCTAssertEqual(DraftPayloadPreview.safeAccent(""), CodepetTheme.accentPurple)
        XCTAssertEqual(DraftPayloadPreview.safeAccent("0a1430"), CodepetTheme.accentPurple,
                       "a missing # is not a valid hex here")
        XCTAssertEqual(DraftPayloadPreview.safeAccent("#0a143"), CodepetTheme.accentPurple,
                       "five digits is neither 3 nor 6")
    }

    func testAValidAccentIsUsed() {
        XCTAssertNotEqual(DraftPayloadPreview.safeAccent("#0a1430"), CodepetTheme.accentPurple)
        XCTAssertNotEqual(DraftPayloadPreview.safeAccent("#abc"), CodepetTheme.accentPurple)
    }

    /// Murror's own accent must survive the validator — it is the one on screen.
    func testMurrorAccentSurvivesValidation() throws {
        let entry = DemoProject.murror.deliverable(for: "Build the Murror landing page")
        let json = try XCTUnwrap(entry.payloadJSON)
        let p = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let accent = try XCTUnwrap(p.site?.accent)
        XCTAssertNotEqual(DraftPayloadPreview.safeAccent(accent), CodepetTheme.accentPurple,
                          "\(accent) was rejected by the validator")
    }

    // MARK: - The cap

    func testHeightCapIsTheSpecValue() {
        XCTAssertEqual(DraftPayloadPreview.maxHeight, 180)
    }

    /// Every structured Murror payload renders inside the cap. `ImageRenderer` is the only way
    /// to measure this — Screen Recording is denied on the build machine.
    @MainActor
    func testEveryMurrorPreviewFitsTheCap() throws {
        for entry in DemoProject.murror.deliverables where entry.payloadJSON != nil {
            let kind = try XCTUnwrap(DeliverableKind(rawValue: entry.kind))
            let d = try deliverable(kind, payloadJSON: entry.payloadJSON)
            let renderer = ImageRenderer(content:
                DraftPayloadPreview(deliverable: d).frame(width: 320))
            let image = try XCTUnwrap(renderer.nsImage, "\(entry.kind) rendered nothing")
            XCTAssertLessThanOrEqual(image.size.height, DraftPayloadPreview.maxHeight + 1,
                                     "\(entry.kind) is \(image.size.height)pt tall")
            XCTAssertGreaterThan(image.size.height, 8, "\(entry.kind) rendered empty")
        }
    }
}
