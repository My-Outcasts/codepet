import XCTest
@testable import codepet

/// The panel itself cannot be tested — the same limit `AttachmentPicker` records for its
/// `NSOpenPanel`. `write(_:to:)` is split out for exactly that reason: it is everything the
/// panel does once the founder has chosen, and it runs from a temp directory.
final class DeliverableExporterTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWritesEveryFileAndReturnsWhereTheyLanded() throws {
        let files = [ExportFile(name: "a.md", data: Data("alpha".utf8)),
                     ExportFile(name: "b.txt", data: Data("beta".utf8))]
        let urls = try DeliverableExporter.write(files, to: dir)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "alpha")
        XCTAssertEqual(try String(contentsOf: urls[1], encoding: .utf8), "beta")
    }

    /// Exporting the same deliverable twice must not silently destroy the first file.
    func testASecondExportDoesNotOverwriteTheFirst() throws {
        let files = [ExportFile(name: "plan.md", data: Data("first".utf8))]
        _ = try DeliverableExporter.write(files, to: dir)
        let second = try DeliverableExporter.write(
            [ExportFile(name: "plan.md", data: Data("second".utf8))], to: dir)
        XCTAssertEqual(second[0].lastPathComponent, "plan-2.md")
        let firstURL = dir.appendingPathComponent("plan.md")
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "first")
    }

    /// A name cannot escape the directory the founder chose.
    ///
    /// Compared by `.path`, not by `URL ==`. `deletingLastPathComponent()` returns a URL WITH
    /// a trailing slash and URL equality is string-based, so `file:///tmp/x/` != `file:///tmp/x`
    /// and an assertion on the URLs fails while the paths are identical.
    func testANameCannotClimbOutOfTheChosenDirectory() throws {
        let urls = try DeliverableExporter.write(
            [ExportFile(name: "../escaped.md", data: Data("x".utf8))], to: dir)
        XCTAssertEqual(urls[0].deletingLastPathComponent().standardizedFileURL.path,
                       dir.standardizedFileURL.path)
        // The security property, not just the neighbourhood: the `../` is gone.
        XCTAssertEqual(urls[0].lastPathComponent, "escaped.md")
    }

    func testEndToEndADeliverableBecomesFilesOnDisk() throws {
        let d = Deliverable(kind: .checklist, title: "Release rhythm", body: "",
                            payload: DeliverablePayload(items: [
                                ChecklistItem(t: "Tag the build", done: false)]))
        let urls = try DeliverableExporter.write(DeliverableExport.files(for: d), to: dir)
        XCTAssertEqual(urls[0].lastPathComponent, "release-rhythm.md")
        let text = try String(contentsOf: urls[0], encoding: .utf8)
        XCTAssertTrue(text.contains("- [ ] Tag the build"), text)
    }

    // MARK: - I3: a write failure must not be swallowed

    /// A directory that cannot exist — its parent is a FILE, not a folder, so the filesystem
    /// refuses to create anything under it. This is the testable half of "sandbox denial /
    /// read-only volume / full disk": the write itself throws, and it must actually throw
    /// rather than `try?`-vanish. Asserts: `write(_:to:)` throws (does not silently return),
    /// and the failure surfaces before any file is reported as landed.
    func testWriteThrowsWhenTheDirectoryCannotBeWritten() throws {
        let blockingFile = dir.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blockingFile)
        let unwritable = blockingFile.appendingPathComponent("child")

        XCTAssertThrowsError(
            try DeliverableExporter.write([ExportFile(name: "a.md", data: Data("x".utf8))],
                                           to: unwritable)
        )
    }

    /// A throw partway through a multi-file set must say how many files landed before it,
    /// not just that something went wrong. The first file is ordinary; the second's NAME
    /// (300 `x`s) exceeds the filesystem's 255-byte filename limit — `unusedURL` never
    /// rejects it (nothing that long already exists, so there is no collision to dodge), but
    /// the actual `Data.write(to:)` does, deterministically and without touching permissions.
    func testAPartialWriteReportsHowManyFilesLanded() throws {
        let tooLongName = String(repeating: "x", count: 300) + ".md"
        let files = [ExportFile(name: "a.md", data: Data("first".utf8)),
                     ExportFile(name: tooLongName, data: Data("second".utf8))]

        do {
            _ = try DeliverableExporter.write(files, to: dir)
            XCTFail("expected the over-long filename to throw")
        } catch let partial as DeliverableExporter.PartialWrite {
            XCTAssertEqual(partial.landed, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.md").path))
        }
    }

    /// `DeliverableExporter.save`'s public contract: cancelling must never look like a
    /// failure. `Outcome` itself carries this — `.cancelled` and `.failed` are distinct
    /// cases — this test pins that they stay distinct rather than collapsing back to a
    /// single boolean that cannot tell them apart.
    func testCancelledAndFailedAreDistinctOutcomes() {
        XCTAssertNotEqual(DeliverableExporter.Outcome.cancelled,
                          DeliverableExporter.Outcome.failed(landed: 0))
        XCTAssertEqual(DeliverableExporter.Outcome.failed(landed: 2),
                       DeliverableExporter.Outcome.failed(landed: 2))
        XCTAssertNotEqual(DeliverableExporter.Outcome.failed(landed: 1),
                          DeliverableExporter.Outcome.failed(landed: 2))
    }
}
