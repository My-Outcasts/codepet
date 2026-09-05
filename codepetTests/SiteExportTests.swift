// codepetTests/SiteExportTests.swift
import XCTest
@testable import codepet

/// Guards on a produced landing page being able to leave the app.
///
/// `SiteViewer` had exactly two affordances — a Preview/Code picker and Copy HTML — over an
/// in-app `WKWebView` fed an HTML string that was never written anywhere. So a founder could
/// look at their own landing page inside a dock column or paste raw markup onto the clipboard,
/// and had no way to open it in a browser. Reported by the founder twice: once on 4 Sep, and
/// again on 5 Sep with a screenshot, after it had been specced and planned and not built.
final class SiteExportTests: XCTestCase {

    // MARK: - Naming and writing

    /// Derived, not random: opening the same page twice must replace one file rather than
    /// litter the temp directory, and a browser reload must show the current draft.
    func testTheFilenameIsDerivedFromTheDeliverableId() {
        let a = SiteExport.fileURL(forDeliverableId: "demo-mur-site")
        let b = SiteExport.fileURL(forDeliverableId: "demo-mur-site")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.lastPathComponent.contains("demo-mur-site"), a.lastPathComponent)
        XCTAssertEqual(a.pathExtension, "html")
    }

    func testDifferentDeliverablesGetDifferentFiles() {
        XCTAssertNotEqual(SiteExport.fileURL(forDeliverableId: "a"),
                          SiteExport.fileURL(forDeliverableId: "b"))
    }

    /// **The one that matters for safety.** Ids are UUIDs in production and `demo-mur-site` in
    /// fixtures, but an id is only a `String` and nothing in the type system stops a future one
    /// carrying a path separator. `../../etc/passwd` must not escape the directory.
    func testAnIdWithPathSeparatorsCannotEscapeTheDirectory() {
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        for nasty in ["../escape", "a/b/c", "..", "/absolute", "with space", ""] {
            let url = SiteExport.fileURL(forDeliverableId: nasty).standardizedFileURL
            XCTAssertTrue(url.deletingLastPathComponent().path.hasPrefix(tmp),
                          "\(nasty) escaped to \(url.path)")
            XCTAssertEqual(url.pathExtension, "html", nasty)
        }
    }

    func testWritingProducesExactlyTheHTMLGiven() throws {
        let url = SiteExport.fileURL(forDeliverableId: "write-test")
        defer { try? FileManager.default.removeItem(at: url) }
        let html = "<!doctype html><html><body>hi</body></html>"
        try SiteExport.write(html: html, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), html)
    }

    /// A Redo must not show the founder a stale page.
    func testWritingIsIdempotentAndOverwrites() throws {
        let url = SiteExport.fileURL(forDeliverableId: "overwrite-test")
        defer { try? FileManager.default.removeItem(at: url) }
        try SiteExport.write(html: "<p>first</p>", to: url)
        try SiteExport.write(html: "<p>second</p>", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "<p>second</p>")
    }

    /// Fail-soft: an unwritable destination throws so the caller can surface an error. It must
    /// never trap — a founder pressing a button should not crash the app.
    func testAnUnwritableDestinationThrows() {
        let bad = URL(fileURLWithPath: "/System/definitely-not-writable-\(UUID())/x.html")
        XCTAssertThrowsError(try SiteExport.write(html: "<p>x</p>", to: bad))
    }

    // MARK: - The label

    /// Not "Open" alone. The chat draft card already carries an "Open the live page" cue that
    /// routes to this in-app viewer; a second, differently-destined "Open" on the same path is
    /// the confusion this wording avoids.
    func testTheLabelNamesTheBrowser() {
        XCTAssertEqual(SiteViewer.openLabel(.en), "Open in browser")
        XCTAssertEqual(SiteViewer.openLabel(.vi), "Mở trong trình duyệt")
    }

    /// The app ships bilingual; a missing translation renders English in a Vietnamese UI.
    func testBothLabelsAreNonEmptyAndDifferent() {
        XCTAssertFalse(SiteViewer.openLabel(.en).isEmpty)
        XCTAssertFalse(SiteViewer.openLabel(.vi).isEmpty)
        XCTAssertNotEqual(SiteViewer.openLabel(.en), SiteViewer.openLabel(.vi))
    }

    /// The browser must show the same page the preview does, not a re-derivation. Asserted
    /// against the real Murror fixture rather than a stub.
    func testTheWrittenFileMatchesWhatThePreviewRenders() throws {
        let entry = try XCTUnwrap(DemoProject.murror.deliverables.first { $0.kind == "site" })
        let payload = try JSONDecoder().decode(
            DeliverablePayload.self, from: Data(try XCTUnwrap(entry.payloadJSON).utf8))
        let site = try XCTUnwrap(payload.site)
        let html = SiteViewer.buildHTML(site)
        let url = SiteExport.fileURL(forDeliverableId: "fixture-parity")
        defer { try? FileManager.default.removeItem(at: url) }
        try SiteExport.write(html: html, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), html)
        XCTAssertTrue(html.lowercased().contains("<!doctype html"), "not a whole document")
    }
}
