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
    func testANameCannotClimbOutOfTheChosenDirectory() throws {
        let urls = try DeliverableExporter.write(
            [ExportFile(name: "../escaped.md", data: Data("x".utf8))], to: dir)
        XCTAssertEqual(urls[0].deletingLastPathComponent().standardizedFileURL,
                       dir.standardizedFileURL)
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
}
