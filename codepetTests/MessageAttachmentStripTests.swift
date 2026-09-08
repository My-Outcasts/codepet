import XCTest
@testable import codepet

/// What the founder's own bubble draws when she attached something.
///
/// This suite exists because the field it renders was written, replayed and billed for
/// **months without any view reading it**. `CompanyStore.sendMessage` stamps
/// `CopilotMessage.attachments` and reads it back to build `history[].attachments`, so the
/// model's memory of an image worked perfectly — while the founder's own transcript showed
/// her a bare sentence and no trace of the three screenshots she had just sent (reported
/// 8 Sep). A round trip that is correct on the wire and invisible on screen is exactly the
/// class of defect that survives, so the thumbnail cache — the remaining pure, checkable
/// part of the strip — is exercised here. (The strip used to route attachments through a
/// `MessageAttachmentLayout.split` that grouped images before non-images; that reordered
/// the founder's pick order and was deleted — see `MessageAttachments.swift`.)
@MainActor
final class MessageAttachmentStripTests: XCTestCase {

    private func att(_ name: String, _ kind: AttachmentKind, data: String = "AAAA") -> ChatAttachment {
        ChatAttachment(id: name, kind: kind, filename: name,
                       mediaType: ChatAttachment.mediaType(for: kind, pathExtension: "png"),
                       data: data, byteCount: 4)
    }

    /// A 1x1 red PNG. Real bytes, because the point of the cache is that it DECODES —
    /// asserting on a fixture that no decoder ever accepts would pass while the strip
    /// renders nothing.
    private var onePixelPNG: String {
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    }

    // MARK: - The thumbnail cache

    /// The whole reason the cache exists: `data` is base64 of an image up to 2576px on its
    /// long edge, and SwiftUI evaluates `body` constantly. Decoding per evaluation is the
    /// per-frame class of cost the dock-resize fix was about.
    func testDecodesRealImageBytes() {
        let cache = AttachmentThumbnailCache()
        XCTAssertNotNil(cache.image(for: att("a.png", .image, data: onePixelPNG)))
    }

    /// Same attachment twice returns the SAME object, not an equal one — that identity IS
    /// the caching. An `XCTAssertEqual` on two NSImages would pass without any cache at all.
    func testSecondLookupReturnsTheCachedInstance() {
        let cache = AttachmentThumbnailCache()
        let a = att("a.png", .image, data: onePixelPNG)
        guard let first = cache.image(for: a) else { return XCTFail("did not decode") }
        XCTAssertTrue(cache.image(for: a) === first)
    }

    /// `ChatAttachment.id` is `path#byteCount`, so an EDITED file is a different attachment.
    /// Keying on filename would serve the stale pixels for the re-picked file.
    func testAnEditedFileIsNotServedTheOldPixels() {
        let cache = AttachmentThumbnailCache()
        let original = ChatAttachment(id: "/tmp/shot.png#100", kind: .image, filename: "shot.png",
                                      mediaType: "image/png", data: onePixelPNG, byteCount: 100)
        let edited = ChatAttachment(id: "/tmp/shot.png#200", kind: .image, filename: "shot.png",
                                    mediaType: "image/png", data: onePixelPNG, byteCount: 200)
        guard let a = cache.image(for: original), let b = cache.image(for: edited) else {
            return XCTFail("did not decode")
        }
        XCTAssertFalse(a === b)
    }

    /// Undecodable base64 must return nil rather than trap or hand back a blank image: the
    /// strip falls back to a chip, which still tells her the file was sent.
    func testRefusesBytesThatAreNotAnImage() {
        let cache = AttachmentThumbnailCache()
        XCTAssertNil(cache.image(for: att("a.png", .image, data: "bm90IGFuIGltYWdl")))
    }
}
