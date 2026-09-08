import XCTest
@testable import codepet

/// The picker encodes. It does not decide.
///
/// This suite exists because it used to decide, invisibly. `pickAndEncode` trimmed with
/// `panel.urls.prefix(limit)`, and `rejected` collected only files that FAILED TO ENCODE —
/// so a file removed by the trim was reported nowhere. The founder picked four images, three
/// appeared, and nothing was said (8 Sep). `AttachmentBudget.admit` never saw the fourth, so
/// the refusal machinery that would have named it was never reachable.
@MainActor
final class AttachmentPickerEncodeTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-picker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A 1x1 PNG on disk, named `name`.
    private func png(_ name: String) throws -> URL {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let url = dir.appendingPathComponent(name)
        try Data(base64Encoded: b64)!.write(to: url)
        return url
    }

    /// **The reported bug.** More files than the cap must all be encoded and handed on, so
    /// that `admit` — the only thing allowed to refuse — can name the ones that do not fit.
    func testEncodesEveryFileEvenPastTheCap() throws {
        let urls = try (0..<(ChatAttachment.max + 4)).map { try png("shot\($0).png") }
        let out = AttachmentPicker.encodeAll(urls)
        XCTAssertEqual(out.attachments.count, ChatAttachment.max + 4)
        XCTAssertTrue(out.rejected.isEmpty)
    }

    /// Order is the founder's pick order, because the notice names files in that order.
    func testKeepsPickOrder() throws {
        let urls = try ["b.png", "a.png", "c.png"].map { try png($0) }
        XCTAssertEqual(AttachmentPicker.encodeAll(urls).attachments.map(\.filename),
                       ["b.png", "a.png", "c.png"])
    }

    /// `rejected` keeps its ONE meaning: the picker could not read this file. It is no
    /// longer overloaded with "silently over the count", which is what hid the bug.
    func testRejectedMeansUnreadableAndNothingElse() throws {
        let good = try png("ok.png")
        let bad = dir.appendingPathComponent("notes.sketch")
        try Data("x".utf8).write(to: bad)
        let out = AttachmentPicker.encodeAll([good, bad])
        XCTAssertEqual(out.attachments.map(\.filename), ["ok.png"])
        XCTAssertEqual(out.rejected, ["notes.sketch"])
    }

    /// Everything the picker returns must be admissible input: `admit` decides, and with
    /// room for all of them it takes all of them.
    func testWhatItReturnsIsWhatAdmitJudges() throws {
        let urls = try (0..<3).map { try png("s\($0).png") }
        let out = AttachmentPicker.encodeAll(urls)
        let admission = AttachmentBudget.admit(out.attachments, to: [])
        XCTAssertEqual(admission.accepted.count, 3)
        XCTAssertTrue(admission.refused.isEmpty)
    }

    // MARK: - Resolving what a drag actually hands us

    /// **The drop path handled only `Data` and would have looked inert for any drag source
    /// that hands back an `NSURL`.** Which type arrives depends on the source, so all of
    /// them are pinned here rather than trusted.
    func testResolvesAFileURLFromEveryShapeADragCanHandBack() throws {
        let file = try png("dropped.png")
        XCTAssertEqual(AttachmentPicker.fileURL(from: file), file, "a URL must pass through")
        XCTAssertEqual(AttachmentPicker.fileURL(from: file as NSURL), file, "an NSURL must convert")
        XCTAssertEqual(AttachmentPicker.fileURL(from: file.dataRepresentation), file,
                       "a Data representation must decode")
    }

    /// Anything that is not a file URL resolves to nil, so the caller can COUNT it and say so.
    /// Returning nil silently is only safe because `acceptingDrops` reports the count.
    func testRefusesWhatIsNotAFileURL() {
        XCTAssertNil(AttachmentPicker.fileURL(from: nil))
        XCTAssertNil(AttachmentPicker.fileURL(from: 42))
        XCTAssertNil(AttachmentPicker.fileURL(from: Data([0xFF, 0xFE])))
        XCTAssertNil(AttachmentPicker.fileURL(from: "https://example.com"),
                     "a web URL is not a file and must not be attached")
    }
}
