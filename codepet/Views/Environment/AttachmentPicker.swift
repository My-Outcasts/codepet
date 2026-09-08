// codepet/Views/Environment/AttachmentPicker.swift
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Turns a file the founder chose into a `ChatAttachment` — spec §7.2.
///
/// Lives beside `ProjectLinker` because it is the same kind of thing: the one place
/// an `NSOpenPanel` is allowed to exist, so no view has to know about AppKit.
///
/// **Everything here is client-side.** No network, no Anthropic call, no Firebase.
/// The downscale is where the cost of an attachment is actually decided, and it
/// happens on this side of the wire — which is why tuning it never needs a deploy.
enum AttachmentPicker {

    /// Open the panel and encode whatever the founder picked.
    ///
    /// **This function no longer has a limit, and that is the fix.** It used to take one
    /// and trim with `panel.urls.prefix(limit)` — while `rejected` collected only files that
    /// FAILED TO ENCODE, so a file removed by the trim was reported nowhere. The founder
    /// picked four images, three appeared, and nothing was said (8 Sep). The panel had
    /// offered her a fourth selection and then taken it back in silence.
    ///
    /// `AttachmentBudget.admit` owns both caps, is pure and is tested, and its `.tooMany`
    /// refusal has always rendered a message naming the files. That machinery was simply
    /// unreachable, because this function trimmed the list before `admit` could see it. So
    /// there is now exactly one place a file can be refused, and it must say why.
    ///
    /// **`unsupported` and `oversized` are two different buckets, not one `rejected` list.**
    /// A 16 MB `mml-book.pdf` was told "Codepet can't read mml-book.pdf" (reported 8 Sep) —
    /// false and unactionable, since PDFs are supported and the real problem is
    /// `ChatAttachment.maxBytes`. `unsupported` means the format or file itself could not be
    /// read at all; `oversized` means it was read fine and is simply too big. The founder's
    /// next move differs by bucket, so the message has to.
    static func pickAndEncode() -> (attachments: [ChatAttachment], unsupported: [String], oversized: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ChatAttachment.allowedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "Attach"
        panel.message = "Screenshots, PDFs, and text files. Images are resized before sending."

        guard panel.runModal() == .OK else { return ([], [], []) }
        return encodeAll(panel.urls)
    }

    /// Encode a set of files, keeping the founder's order.
    ///
    /// Split out from the panel so it is reachable from a test with fixture URLs — the
    /// `NSOpenPanel` is the only part of this file a test cannot drive.
    ///
    /// **Deliberately has no cap of any kind.** A limit here is a second place a file can
    /// disappear, and the last one produced a defect the founder could see and we could
    /// not explain. `encode` already refuses a single file over `ChatAttachment.maxBytes`,
    /// which bounds the cost; everything else is `admit`'s to judge.
    ///
    /// `unsupported` carries both `.unsupported` (extension we don't handle) and
    /// `.unreadable` (on disk but could not be opened) — both mean "Codepet can't read
    /// this", which is true for either. `oversized` carries `.tooBig` — supported and
    /// readable, just over `ChatAttachment.maxBytes` — because that file needs a different
    /// sentence and a different fix.
    static func encodeAll(_ urls: [URL]) -> (attachments: [ChatAttachment], unsupported: [String], oversized: [String]) {
        var out: [ChatAttachment] = []
        var unsupported: [String] = []
        var oversized: [String] = []
        for url in urls {
            switch encode(url) {
            case .ok(let a): out.append(a)
            case .unsupported, .unreadable: unsupported.append(url.lastPathComponent)
            case .tooBig: oversized.append(url.lastPathComponent)
            }
        }
        return (out, unsupported, oversized)
    }

    /// Why a file could not be encoded — three reasons that need three different sentences,
    /// because the founder's next action differs. "Codepet can't read mml-book.pdf" was shown
    /// for a 16 MB PDF (reported 8 Sep): the format is supported and the message said the
    /// opposite, so the only move it suggested was to give up on PDFs.
    enum Encoded {
        case ok(ChatAttachment)
        /// An extension `ChatAttachment.kind(forPathExtension:)` does not handle.
        case unsupported
        /// On disk but unreadable — permissions, a broken alias, a vanished file.
        case unreadable
        /// Over `ChatAttachment.maxBytes`. Supported, just too big — and for an image this is
        /// measured AFTER the downscale, so it is mostly reachable by PDFs and text files.
        case tooBig
    }

    /// Encode one file. See `Encoded` for why a failure is not just `nil` any more.
    ///
    /// Exposed rather than private so a future test can drive it from a fixture URL
    /// without an `NSOpenPanel`, which is the only part of this file a test can't run.
    static func encode(_ url: URL) -> Encoded {
        let ext = url.pathExtension
        guard let kind = ChatAttachment.kind(forPathExtension: ext) else { return .unsupported }
        guard let raw = try? Data(contentsOf: url) else { return .unreadable }

        // The cap is on the ORIGINAL bytes for text and pdf. An image is measured
        // after downscaling, because downscaling is exactly what makes an oversized
        // screenshot acceptable — rejecting it before we shrink it would refuse the
        // most common attachment there is.
        let payload: Data
        // **The declared media type has to describe the bytes we END UP with.**
        // `downscaledImageData` re-encodes every non-JPEG source as PNG, so a resized
        // .webp or .gif is PNG bytes — and it was being declared `image/webp` /
        // `image/gif`, a header that contradicts its own payload. Both are legal values,
        // so nothing drops it here or in `functions/`; it fails at the API, on a turn
        // that looks ordinary from every log we own.
        var mediaType = ChatAttachment.mediaType(for: kind, pathExtension: ext)
        switch kind {
        case .image:
            if let smaller = downscaledImageData(raw, pathExtension: ext) {
                payload = smaller
                mediaType = ChatAttachment.downscaledMediaType(pathExtension: ext)
            } else {
                payload = raw   // already small enough, or undecodable — original bytes, original type
            }
        case .pdf, .text:
            payload = raw
        }
        guard payload.count <= ChatAttachment.maxBytes else { return .tooBig }

        return .ok(ChatAttachment(
            // Path plus size: the same file re-picked is the same attachment (so the
            // de-dupe in `adding` catches it), but an edited file is a new one.
            id: "\(url.path)#\(payload.count)",
            kind: kind,
            filename: url.lastPathComponent,
            mediaType: mediaType,
            // `.base64EncodedString()` with no options emits ONE line. Do not pass
            // `.lineLength64Characters` — the API rejects wrapped base64.
            data: payload.base64EncodedString(),
            byteCount: payload.count))
    }

    /// Redraw an image so its long edge is at most `ChatAttachment.imageLongEdge`.
    ///
    /// Returns nil when the image is already small enough or cannot be decoded, in
    /// which case the caller sends the original bytes — a slightly-too-large image
    /// is a cost question, and a dropped attachment is a bug.
    ///
    /// PNG for everything except JPEG sources: re-encoding a photo as PNG can make
    /// it several times larger, which is the opposite of the point.
    private static func downscaledImageData(_ raw: Data, pathExtension ext: String) -> Data? {
        guard let src = NSBitmapImageRep(data: raw) else { return nil }
        let original = CGSize(width: src.pixelsWide, height: src.pixelsHigh)
        let fitted = ChatAttachment.fittedSize(for: original,
                                              longEdge: ChatAttachment.imageLongEdge)
        guard fitted != .zero, fitted != original else { return nil }

        let w = Int(fitted.width), h = Int(fitted.height)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = src.cgImage else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }

        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = fitted
        let isJPEG = ["jpg", "jpeg"].contains(ext.lowercased())
        return rep.representation(
            using: isJPEG ? .jpeg : .png,
            properties: isJPEG ? [.compressionFactor: 0.82] : [:])
    }

    /// Resolve one drag provider's loaded item to a file URL.
    ///
    /// **`loadItem(forTypeIdentifier:)` for `.fileURL` returns `NSSecureCoding`, and which
    /// concrete type arrives depends on the drag SOURCE** — Finder, a browser and another app
    /// do not agree. The first version of the drop path handled only `Data`, so a drag that
    /// handed back a URL object resolved to nothing and the whole feature looked inert.
    ///
    /// **There is deliberately no `NSURL` branch.** One was written and then measured to be
    /// unreachable: Swift bridges `NSURL` to `URL`, so `item as? URL` already catches it, and
    /// deleting the branch changed no test result. It is recorded here so it is not helpfully
    /// re-added.
    ///
    /// **The `Data` branch needs its own `isFileURL` check.**
    /// `URL(dataRepresentation:relativeTo:)` is lenient — it returns a non-nil URL with an
    /// empty scheme for arbitrary bytes, so without the check two garbage bytes resolved to
    /// something this function claimed was a file.
    ///
    /// `Any?` rather than `NSSecureCoding?` so a test can drive it with each shape.
    /// Returns nil for anything that is not a file URL, and the caller must REPORT that
    /// rather than discard it — see `acceptingDrops`.
    static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL { return url }
        // `URL(dataRepresentation:relativeTo:)` is lenient: fed the two raw bytes 0xFF,0xFE
        // (not a real dropped path — see the resolver tests) it still returns a URL, with no
        // scheme and `isFileURL` false, rather than nil. Checking `isFileURL` here matches the
        // guard the String branch already has below and keeps this function's contract —
        // "nil for anything that is not a file URL" — true for garbage bytes too.
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { return url }
        if let s = item as? String, let url = URL(string: s), url.isFileURL { return url }
        return nil
    }
}
