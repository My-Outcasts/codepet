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
}
